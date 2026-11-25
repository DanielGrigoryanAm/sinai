// Command server runs the Sinai API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/auth"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/chats"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/config"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/db"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/messages"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/realtime"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/storage"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/users"
)

func main() {
	if err := run(); err != nil {
		slog.Error("server stopped", "err", err)
		os.Exit(1)
	}
}

func run() error {
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	cfg, err := config.Load()
	if err != nil {
		return err
	}

	pool, err := db.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		return err
	}
	defer pool.Close()

	redisOpts, err := redis.ParseURL(cfg.RedisURL)
	if err != nil {
		return err
	}
	rdb := redis.NewClient(redisOpts)
	defer rdb.Close()
	if err := rdb.Ping(ctx).Err(); err != nil {
		return err
	}

	files, err := storage.New(ctx, storage.Config(cfg.Storage))
	if err != nil {
		return err
	}

	authService := auth.NewService(pool, cfg.JWTSecret, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	userStore := users.NewStore(pool)
	chatStore := chats.NewStore(pool)
	messageStore := messages.NewStore(pool)

	hub := realtime.NewHub()
	bus := realtime.NewBus(rdb, hub)
	go bus.Run(ctx)

	// "Typing" marks go straight to the other members, without storing.
	hub.OnClientEvent = func(ctx context.Context, userID string, e realtime.ClientEvent) {
		if e.Type != "typing" || e.Chat == "" {
			return
		}
		members, err := chatStore.MemberIDs(ctx, e.Chat)
		if err != nil {
			return
		}
		others := members[:0]
		inChat := false
		for _, id := range members {
			if id == userID {
				inChat = true
			} else {
				others = append(others, id)
			}
		}
		if inChat {
			bus.Publish(ctx, realtime.Event{
				Type: "typing", Chat: e.Chat, To: others,
				Data: map[string]string{"userId": userID},
			})
		}
	}
	presence := realtime.NewPresence(rdb, hub)
	go presence.Run(ctx)

	// Tell everyone sharing a chat with the user when they come or go,
	// and remember when they were last connected, for "last seen".
	hub.OnPresence = func(userID string, online bool) {
		ctx := context.Background()
		presence.Set(ctx, userID, online)
		data := map[string]any{"userId": userID, "online": online}
		if !online {
			var at time.Time
			if pool.QueryRow(ctx, `UPDATE users SET last_seen = now()
				WHERE id = $1 RETURNING last_seen`, userID).Scan(&at) == nil {
				data["lastSeen"] = at
			}
		}
		if contacts, err := chatStore.ContactIDs(ctx, userID); err == nil {
			bus.Publish(ctx, realtime.Event{Type: "presence", Data: data, To: contacts})
		}
	}
	userID := func(r *http.Request) string { return auth.UserID(r.Context()) }

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok"))
	})
	auth.NewHandler(authService, userStore).Register(mux)
	users.NewHandler(userStore, userID).Register(mux, authService.Require)
	chatHandler := chats.NewHandler(chatStore, bus, files, userID)
	chatHandler.Online = presence.Online
	chatHandler.Register(mux, authService.Require)
	messages.NewHandler(messageStore, chatStore, bus, files, userID).Register(mux, authService.Require)
	storage.NewHandler(files, chatStore.IsMember, userID).Register(mux, authService.Require)

	// The live connection. Apps send the access token in the header;
	// ?token= is there for clients that can't set headers on sockets.
	mux.HandleFunc("GET /v1/ws", func(w http.ResponseWriter, r *http.Request) {
		token, ok := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
		if !ok {
			token = r.URL.Query().Get("token")
		}
		id, err := authService.Verify(token)
		if err != nil {
			http.Error(w, "unauthorized", http.StatusUnauthorized)
			return
		}
		hub.Serve(w, r, id)
	})

	server := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		<-ctx.Done()
		shutdown, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		server.Shutdown(shutdown)
	}()

	slog.Info("listening", "addr", cfg.HTTPAddr)
	if err := server.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		return err
	}
	return nil
}

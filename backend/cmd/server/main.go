// Command server runs the Sinai API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/DanielGrigoryanAm/sinai/backend/internal/auth"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/config"
	"github.com/DanielGrigoryanAm/sinai/backend/internal/db"
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

	authService := auth.NewService(pool, cfg.JWTSecret, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	userStore := users.NewStore(pool)

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", func(w http.ResponseWriter, _ *http.Request) {
		w.Write([]byte("ok"))
	})
	auth.NewHandler(authService, userStore).Register(mux)
	users.NewHandler(userStore, func(r *http.Request) string {
		return auth.UserID(r.Context())
	}).Register(mux, authService.Require)

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

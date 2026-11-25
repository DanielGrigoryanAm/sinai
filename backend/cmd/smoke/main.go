// Command smoke runs the API end to end against a server on :8080:
// two users, a chat, messages and live events. Run: go run ./cmd/smoke
package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/coder/websocket"
)

const base = "http://localhost:8080"

func call(method, path, token string, body any) (int, map[string]any, []any) {
	var buf io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		buf = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, base+path, buf)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		panic(err)
	}
	defer res.Body.Close()
	raw, _ := io.ReadAll(res.Body)
	var obj map[string]any
	var arr []any
	json.Unmarshal(raw, &obj)
	json.Unmarshal(raw, &arr)
	return res.StatusCode, obj, arr
}

func check(name string, ok bool, detail ...any) {
	mark := "PASS"
	if !ok {
		mark = "FAIL"
		defer os.Exit(1)
	}
	fmt.Println(mark, name, fmt.Sprint(detail...))
}

// fakeFCM stands in for Firebase: it records pushes, and refuses the
// token "dead-token" as unregistered.
type push struct {
	Token, Title, Body string
}

func fakeFCM() chan push {
	got := make(chan push, 50)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /send", func(w http.ResponseWriter, r *http.Request) {
		var body struct {
			Message struct {
				Token        string            `json:"token"`
				Notification map[string]string `json:"notification"`
			} `json:"message"`
		}
		json.NewDecoder(r.Body).Decode(&body)
		m := body.Message
		if m.Token == "dead-token" {
			w.WriteHeader(404)
			w.Write([]byte(`{"error":{"status":"NOT_FOUND","details":[{"errorCode":"UNREGISTERED"}]}}`))
			return
		}
		got <- push{m.Token, m.Notification["title"], m.Notification["body"]}
		w.Write([]byte(`{"name":"ok"}`))
	})
	go http.ListenAndServe("localhost:9099", mux)
	return got
}

func main() {
	pushes := fakeFCM()
	// nextPush waits for a push to token whose body contains want.
	nextPush := func(token, want string) *push {
		for {
			select {
			case p := <-pushes:
				if p.Token == token && strings.Contains(p.Body, want) {
					return &p
				}
			case <-time.After(3 * time.Second):
				return nil
			}
		}
	}

	_, a, _ := call("POST", "/v1/auth/guest", "", map[string]any{"name": "Alice"})
	_, b, _ := call("POST", "/v1/auth/guest", "", map[string]any{"name": "Bob"})
	ta, tb := a["accessToken"].(string), b["accessToken"].(string)
	bobID := b["user"].(map[string]any)["id"].(string)
	aliceID := a["user"].(map[string]any)["id"].(string)

	// Bob listens for live events.
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	ws, _, err := websocket.Dial(ctx, "ws://localhost:8080/v1/ws?token="+tb, nil)
	check("bob websocket connects", err == nil, err)
	events := make(chan map[string]any, 20)
	go func() {
		for {
			_, data, err := ws.Read(ctx)
			if err != nil {
				return
			}
			var e map[string]any
			json.Unmarshal(data, &e)
			events <- e
		}
	}()
	next := func(want string) map[string]any {
		for {
			select {
			case e := <-events:
				if e["type"] == want {
					return e
				}
			case <-time.After(3 * time.Second):
				return nil
			}
		}
	}

	st, chat, _ := call("POST", "/v1/chats", ta, map[string]any{"name": "Куда"})
	code, _ := chat["code"].(string)
	check("alice creates chat", st == 201 && len(code) == 6, code)

	st, _, _ = call("GET", "/v1/chats/"+code+"/messages", tb, nil)
	check("bob can't read before joining", st == 404, st)

	st, joined, _ := call("POST", "/v1/chats/"+code+"/join", tb, nil)
	check("bob joins by code", st == 200 && len(joined["members"].([]any)) == 2)

	st, _, _ = call("PUT", "/v1/devices", tb, map[string]any{"token": "bob-phone", "platform": "ios"})
	check("bob registers his phone", st == 204, st)
	call("PUT", "/v1/devices", ta, map[string]any{"token": "alice-phone", "platform": "android"})
	call("PUT", "/v1/devices", tb, map[string]any{"token": "dead-token", "platform": "android"})

	st, msg, _ := call("POST", "/v1/chats/"+code+"/messages", ta, map[string]any{"text": "Привет!"})
	p := nextPush("bob-phone", "Привет")
	check("bob gets a push", p != nil && p.Title == "Куда" && p.Body == "Alice: Привет!", p)
	check("alice sends", st == 201 && msg["senderName"] == "Alice")
	e := next("message.created")
	check("bob gets it live", e != nil && e["data"].(map[string]any)["text"] == "Привет!")

	st, reply, _ := call("POST", "/v1/chats/"+code+"/messages", tb,
		map[string]any{"text": "Здравствуй", "replyTo": msg["id"]})
	check("bob replies with quote", st == 201 && reply["replyTo"].(map[string]any)["text"] == "Привет!")

	st, _, list := call("GET", "/v1/chats", ta, nil)
	first := list[0].(map[string]any)
	check("chat list: last message and unread", st == 200 &&
		first["lastMessage"].(map[string]any)["text"] == "Здравствуй" && first["unread"] == 1.0,
		first["unread"])

	st, _, _ = call("POST", "/v1/chats/"+code+"/read", ta, nil)
	check("alice marks read", st == 204)
	check("bob sees read mark", next("chat.read") != nil)
	_, _, list = call("GET", "/v1/chats", ta, nil)
	check("unread back to 0", list[0].(map[string]any)["unread"] == 0.0)

	st, reacted, _ := call("PUT", "/v1/chats/"+code+"/messages/"+msg["id"].(string)+"/reaction", tb, map[string]any{"emoji": "❤️"})
	check("bob reacts", st == 200 && reacted["reactions"].(map[string]any)[bobID] == "❤️")
	p = nextPush("alice-phone", "reacted")
	check("alice gets the reaction push", p != nil && strings.HasPrefix(p.Body, "Bob reacted ❤️"), p)

	st, _, _ = call("PATCH", "/v1/chats/"+code+"/messages/"+msg["id"].(string), tb, map[string]any{"text": "hack"})
	check("bob can't edit alice's message", st == 404, st)
	st, edited, _ := call("PATCH", "/v1/chats/"+code+"/messages/"+msg["id"].(string), ta, map[string]any{"text": "Привет всем!"})
	check("alice edits", st == 200 && edited["editedAt"] != nil)
	check("bob sees the edit", next("message.updated") != nil)

	for i := range 35 {
		call("POST", "/v1/chats/"+code+"/messages", ta, map[string]any{"text": fmt.Sprint("n", i)})
	}
	_, _, page1 := call("GET", "/v1/chats/"+code+"/messages", ta, nil)
	last := page1[len(page1)-1].(map[string]any)["id"].(string)
	_, _, page2 := call("GET", "/v1/chats/"+code+"/messages?before="+last, ta, nil)
	check("history pages", len(page1) == 30 && len(page2) == 7, len(page1), "+", len(page2))

	_, _, found := call("GET", "/v1/chats/"+code+"/messages/search?q=всем", tb, nil)
	check("search", len(found) == 1)

	st, _, _ = call("PATCH", "/v1/chats/"+code, tb, map[string]any{"name": "x"})
	check("bob can't rename", st == 403, st)
	st, _, _ = call("PATCH", "/v1/chats/"+code, tb, map[string]any{"game": map[string]any{"pick": "chess"}})
	check("bob can set the game", st == 200)
	call("PATCH", "/v1/chats/"+code, ta, map[string]any{"game": map[string]any{
		"type": "chess", "by": aliceID, "event": "start", "at": 1, "white": aliceID,
		"fen": "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"}})
	p = nextPush("bob-phone", "invites")
	check("bob is invited to play", p != nil && p.Body == "Alice invites you to play chess", p)
	call("PATCH", "/v1/chats/"+code, tb, map[string]any{"game": map[string]any{
		"type": "chess", "by": bobID, "event": "move", "at": 2, "white": aliceID, "black": bobID,
		"fen": "rnbqkbnr/pppp1ppp/8/4p3/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2"}})
	p = nextPush("alice-phone", "move")
	check("alice told it's her turn", p != nil && p.Body == "Bob made a move in chess. Your turn!", p)

	st, _, _ = call("POST", "/v1/chats/"+code+"/messages", ta, map[string]any{"text": "again"})
	nextPush("bob-phone", "again")
	time.Sleep(300 * time.Millisecond)
	out, _ := exec.Command("docker", "compose", "exec", "-T", "postgres", "psql", "-U", "sinai", "-tAc",
		"select count(*) from device_tokens where token = 'dead-token'").Output()
	check("dead token forgotten", strings.TrimSpace(string(out)) == "0", string(out))

	// Files: get an upload URL, PUT the bytes, send the message with it.
	st, up, _ := call("POST", "/v1/chats/"+code+"/uploads", ta,
		map[string]any{"kind": "image", "contentType": "image/jpeg"})
	check("upload url", st == 200 && up["uploadUrl"] != nil, st, up["error"])
	photo := []byte("not really a jpeg, but bytes")
	req, _ := http.NewRequest("PUT", up["uploadUrl"].(string), bytes.NewReader(photo))
	res, err := http.DefaultClient.Do(req)
	check("put to storage", err == nil && res.StatusCode == 200, err)
	st, pic, _ := call("POST", "/v1/chats/"+code+"/messages", ta,
		map[string]any{"imageUrl": up["key"], "imageWidth": 10, "imageHeight": 10})
	imageURL, _ := pic["imageUrl"].(string)
	check("send photo", st == 201 && strings.HasPrefix(imageURL, "/v1/files/chats/"+code+"/images/"), imageURL)

	st, _, _ = call("POST", "/v1/chats/"+code+"/messages", ta,
		map[string]any{"imageUrl": "chats/" + code + "/images/never-uploaded"})
	check("refuses a file never uploaded", st == 400, st)
	st, _, _ = call("POST", "/v1/chats/"+code+"/messages", ta,
		map[string]any{"imageUrl": "chats/OTHER1/images/x"})
	check("refuses another chat's file", st == 400, st)

	req, _ = http.NewRequest("GET", base+imageURL, nil)
	req.Header.Set("Authorization", "Bearer "+tb)
	res, err = http.DefaultClient.Do(req)
	got, _ := io.ReadAll(res.Body)
	check("member downloads it", err == nil && res.StatusCode == 200 && bytes.Equal(got, photo), res.StatusCode)

	_, c, _ := call("POST", "/v1/auth/guest", "", map[string]any{"name": "Carol"})
	req, _ = http.NewRequest("GET", base+imageURL, nil)
	req.Header.Set("Authorization", "Bearer "+c["accessToken"].(string))
	res, _ = http.DefaultClient.Do(req)
	check("outsider can't", res.StatusCode == 404, res.StatusCode)

	// Presence: Bob's socket is open, so he is online.
	_, info, _ := call("GET", "/v1/chats/"+code, ta, nil)
	online := map[string]bool{}
	for _, m := range info["members"].([]any) {
		mm := m.(map[string]any)
		online[mm["userId"].(string)] = mm["online"].(bool)
	}
	check("bob shows online", online[bobID], online)

	ws.Write(ctx, websocket.MessageText, []byte(`{"type":"typing","chat":"`+code+`"}`))
	wa, _, _ := websocket.Dial(ctx, "ws://localhost:8080/v1/ws?token="+ta, nil)
	time.Sleep(200 * time.Millisecond)
	ws.Write(ctx, websocket.MessageText, []byte(`{"type":"typing","chat":"`+code+`"}`))
	aliceEvents := make(chan []byte, 10)
	go func() {
		for {
			_, data, err := wa.Read(ctx)
			if err != nil {
				return
			}
			aliceEvents <- data
		}
	}()
	waitAlice := func(want string) []byte {
		for {
			select {
			case data := <-aliceEvents:
				if bytes.Contains(data, []byte(want)) {
					return data
				}
			case <-time.After(3 * time.Second):
				return nil
			}
		}
	}
	data := waitAlice(`"type":"typing"`)
	check("alice sees bob typing", data != nil, string(data))

	ws.Close(websocket.StatusNormalClosure, "bye")
	data = waitAlice(`"online":false`)
	check("alice sees bob go offline", data != nil && bytes.Contains(data, []byte("lastSeen")), string(data))
	ws, _, _ = websocket.Dial(ctx, "ws://localhost:8080/v1/ws?token="+tb, nil)
	go func() {
		for {
			_, data, err := ws.Read(ctx)
			if err != nil {
				return
			}
			var e map[string]any
			json.Unmarshal(data, &e)
			events <- e
		}
	}()
	data = waitAlice(`"online":true`)
	check("and back online", data != nil, string(data))

	st, _, _ = call("DELETE", "/v1/chats/"+code+"/members/me", tb, nil)
	check("bob leaves", st == 204)
	check("bob told he's out", next("chat.removed") != nil)

	st, _, _ = call("DELETE", "/v1/chats/"+code, ta, nil)
	check("alice deletes chat", st == 204)
	_, _, list = call("GET", "/v1/chats", ta, nil)
	check("chat gone", len(list) == 0)
}

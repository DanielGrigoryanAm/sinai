package push

import (
	"fmt"
	"unicode/utf8"
)

// What pushes say, the same as the Firebase functions did.

const maxBody = 200

func shorten(s string) string {
	if utf8.RuneCountInString(s) <= maxBody {
		return s
	}
	return string([]rune(s)[:maxBody]) + "…"
}

// Describe says what a message is: its text, or Photo / Voice.
func Describe(text string, image, voice bool) string {
	switch {
	case text != "":
		return text
	case image:
		return "📷 Photo"
	case voice:
		return "🎤 Voice message"
	}
	return ""
}

func data(chat, chatName string) map[string]string {
	return map[string]string{"chatCode": chat, "chatName": chatName}
}

func orSomeone(name string) string {
	if name == "" {
		return "Someone"
	}
	return name
}

// NewMessage: named chats show "Chat" / "Sender: text"; unnamed ones the
// sender as the title.
func NewMessage(chat, chatName, sender, what string) Notification {
	sender = orSomeone(sender)
	body := shorten(what)
	n := Notification{Title: sender, Body: body, Data: data(chat, chatName), Tag: chat}
	if chatName != "" {
		n.Title = chatName
		n.Body = sender + ": " + body
	}
	return n
}

func Reaction(chat, chatName, messageID, reactor, emoji, quoted string) Notification {
	reactor = orSomeone(reactor)
	title := chatName
	if title == "" {
		title = reactor
	}
	return Notification{
		Title: title,
		Body:  fmt.Sprintf("%s reacted %s to: %s", reactor, emoji, shorten(quoted)),
		Data:  data(chat, chatName),
		Tag:   "reaction-" + messageID,
	}
}

var gameNames = map[string]string{"ttt": "tic-tac-toe", "chess": "chess", "checkers": "checkers"}

// Game says what a game write means for the others, and to whom it goes:
// an invite to everyone, "your turn" to the player to move (everyone
// while that side is free), or the result. ok is false when the write
// isn't a start or a move.
func Game(chat, chatName, actor string, members []string, before, after map[string]any) (n Notification, to []string, ok bool) {
	by, _ := after["by"].(string)
	at, _ := after["at"]
	if by == "" || at == nil || fmt.Sprint(at) == fmt.Sprint(before["at"]) {
		return Notification{}, nil, false
	}
	for _, id := range members {
		if id != by {
			to = append(to, id)
		}
	}
	actor = orSomeone(actor)
	kind, _ := after["type"].(string)
	if kind == "" {
		kind = "ttt"
	}
	game := gameNames[kind]
	if game == "" {
		game = "a game"
	}

	var body string
	result := after["result"]
	if result == nil {
		result = after["winner"]
	}
	switch {
	case after["event"] == "start":
		body = fmt.Sprintf("%s invites you to play %s", actor, game)
	case result == "draw":
		body = fmt.Sprintf("Your %s game with %s ended in a draw", game, actor)
	case result != nil:
		body = fmt.Sprintf("%s won the %s game", actor, game)
	default:
		if next := playerToMove(after); next != "" && next != by {
			to = []string{next}
		}
		body = fmt.Sprintf("%s made a move in %s. Your turn!", actor, game)
	}
	title := chatName
	if title == "" {
		title = actor
	}
	return Notification{Title: title, Body: body, Data: data(chat, chatName), Tag: "game-" + chat}, to, true
}

func playerToMove(game map[string]any) string {
	side, _ := game["turn"].(string)
	if game["type"] == "chess" {
		if fen, _ := game["fen"].(string); fen != "" {
			for i := 0; i < len(fen); i++ {
				if fen[i] == ' ' && i+1 < len(fen) {
					side = string(fen[i+1])
					break
				}
			}
		}
	}
	key := map[string]string{"w": "white", "b": "black", "x": "x", "o": "o"}[side]
	id, _ := game[key].(string)
	return id
}

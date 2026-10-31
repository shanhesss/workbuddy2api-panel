package upstream

import (
	"net/http"

	"github.com/misakano7545/workbuddy2api-panel/internal/auth"
)

// do is the single account-aware HTTP exit, including nonstandard header families.
func (c *Client) do(req *http.Request, a *auth.Auth, chat bool) (*http.Response, error) {
	client := c.HTTP
	if chat {
		client = c.chatHTTP()
	}
	if c.ProxyPool == nil || a == nil {
		return client.Do(req)
	}
	return c.ProxyPool.Do(client, req, a.UID)
}

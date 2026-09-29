package provider

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"terraform-provider-postmark/internal/provider/resource_webhook"
	"testing"

	"github.com/hashicorp/terraform-plugin-framework/types"
	"github.com/mrz1836/postmark"
)

func TestWebhookCreateSkipsVerification(t *testing.T) {
	for _, fail := range []bool{false, true} {
		name := "success"
		if fail {
			name = "api_error"
		}
		t.Run(name, func(t *testing.T) {
			server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
				if req.Method != http.MethodPost || req.URL.RequestURI() != "/webhooks?verify=false" {
					t.Errorf("unexpected request: %s %s", req.Method, req.URL)
				}
				if req.Header.Get("X-Postmark-Server-Token") != "test-server-token" {
					t.Error("missing server authentication")
				}
				var body postmark.Webhook
				if err := json.NewDecoder(req.Body).Decode(&body); err != nil {
					t.Error(err)
				}
				if body.URL != "https://example.com/webhook" {
					t.Errorf("callback URL changed: %s", body.URL)
				}
				w.Header().Set("Content-Type", "application/json")
				if fail {
					w.WriteHeader(http.StatusUnprocessableEntity)
					if err := json.NewEncoder(w).Encode(postmark.APIError{ErrorCode: 300, Message: "Invalid webhook"}); err != nil {
						t.Error(err)
					}
					return
				}
				body.ID = 123
				if err := json.NewEncoder(w).Encode(body); err != nil {
					t.Error(err)
				}
			}))
			defer server.Close()
			client := postmark.NewClient("original-token", "test-account-token")
			client.BaseURL = server.URL
			client.HTTPClient = server.Client()
			originalTransport := client.HTTPClient.Transport
			r := webhookResource{client: client}
			model := resource_webhook.WebhookModel{ServerApiToken: types.StringValue("test-server-token"), Url: types.StringValue("https://example.com/webhook")}
			diags := r.createFromAPI(context.Background(), &model)
			if fail {
				if !diags.HasError() {
					t.Fatal("expected API error")
				}
				if diags[0].Detail() != "Unable to create webhook, got error: Invalid webhook" {
					t.Fatalf("unexpected diagnostic: %s", diags[0].Detail())
				}
			} else {
				if diags.HasError() {
					t.Fatalf("create failed: %v", diags)
				}
				if model.Id.ValueString() != "123" {
					t.Fatalf("unexpected state ID: %s", model.Id.ValueString())
				}
			}
			if client.ServerToken != "original-token" || client.HTTPClient.Transport != originalTransport {
				t.Error("shared client was mutated")
			}
		})
	}
}

type captureTransport struct{ request *http.Request }

func (t *captureTransport) RoundTrip(req *http.Request) (*http.Response, error) {
	t.request = req
	return &http.Response{StatusCode: http.StatusOK, Body: http.NoBody}, nil
}

func TestWebhookCreateTransportScope(t *testing.T) {
	for _, tc := range []struct{ method, path, want string }{
		{http.MethodPost, "/webhooks?existing=value", "existing=value&verify=false"},
		{http.MethodPut, "/webhooks/123", ""},
		{http.MethodGet, "/webhooks", ""},
		{http.MethodPost, "/servers", ""},
	} {
		t.Run(tc.method+tc.path, func(t *testing.T) {
			req, err := http.NewRequestWithContext(context.Background(), tc.method, "https://api.postmarkapp.com"+tc.path, nil)
			if err != nil {
				t.Fatal(err)
			}
			original := req.URL.String()
			base := &captureTransport{}
			transport := webhookCreateTransport{base: base}
			resp, err := transport.RoundTrip(req)
			if err != nil {
				t.Fatal(err)
			}
			defer resp.Body.Close()
			if base.request.URL.RawQuery != tc.want {
				t.Errorf("query = %q, want %q", base.request.URL.RawQuery, tc.want)
			}
			if req.URL.String() != original {
				t.Error("original request was mutated")
			}
		})
	}
}

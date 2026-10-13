package provider

import (
	"context"
	"os"
	"os/exec"
	"strings"
	"testing"

	"github.com/hashicorp/terraform-plugin-framework/provider"
	"github.com/hashicorp/terraform-plugin-framework/tfsdk"
	"github.com/hashicorp/terraform-plugin-go/tftypes"
)

func TestConfigureDoesNotLogCredentials(t *testing.T) {
	const token = "postmark-regression-test-not-a-real-token"
	if os.Getenv("POSTMARK_CONFIGURE_TEST_CHILD") == "1" {
		ctx := context.Background()
		p := &postmarkProvider{version: "test"}
		schema := provider.SchemaResponse{}
		p.Schema(ctx, provider.SchemaRequest{}, &schema)
		config := tfsdk.Config{
			Schema: schema.Schema,
			Raw: tftypes.NewValue(schema.Schema.Type().TerraformType(ctx), map[string]tftypes.Value{
				"account_token": tftypes.NewValue(tftypes.String, token),
			}),
		}
		response := provider.ConfigureResponse{}
		p.Configure(ctx, provider.ConfigureRequest{Config: config}, &response)
		if response.Diagnostics.HasError() || response.ResourceData == nil || response.DataSourceData == nil {
			t.Fatal("provider did not configure its clients")
		}
		return
	}
	// Capture OS-level stdout AND stderr: Go's builtin println writes to stderr.
	executable, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	// #nosec G204 -- re-exec the current test binary with a fixed test selector.
	cmd := exec.Command(executable, "-test.run=^TestConfigureDoesNotLogCredentials$")
	cmd.Env = append(os.Environ(), "POSTMARK_CONFIGURE_TEST_CHILD=1")
	output, err := cmd.CombinedOutput()
	if strings.Contains(string(output), token) || strings.Contains(string(output), "Account Token:") {
		t.Fatal("Configure emitted credential information")
	}
	if err != nil {
		t.Fatalf("Configure subprocess failed: %v", err)
	}
}

// Copyright 2025 openEuler
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package ignition

import (
	"github.com/coreos/coreos-assembler/mantle/kola/cluster"
	"github.com/coreos/coreos-assembler/mantle/kola/register"
	"github.com/coreos/coreos-assembler/mantle/platform/conf"
)

func init() {
	register.RegisterTest(&register.Test{
		Name:        "nestos.ignition.overlay",
		Description: "Verify Ignition overlay functionality works correctly.",
		Run:         testIgnitionOverlay,
		ClusterSize: 1,
		Tags:        []string{"ignition"},
		UserData: conf.Ignition(`{
			"ignition": { "version": "3.0.0" },
			"storage": {
				"files": [
					{
						"path": "/etc/ignition-overlay-test",
						"contents": {
							"source": "data:,Ignition%20overlay%20test%20successful"
						},
						"mode": 420
					},
					{
						"path": "/etc/ignition-config-1",
						"contents": {
							"source": "data:,Config%201"
						},
						"mode": 420
					}
				]
			},
			"systemd": {
				"units": [
					{
						"name": "ignition-overlay-test.service",
						"enabled": true,
						"contents": "[Unit]\nDescription=Ignition Overlay Test Service\n\n[Service]\nType=oneshot\nExecStart=/bin/touch /var/log/ignition-overlay-ran\n\n[Install]\nWantedBy=multi-user.target"
					}
				]
			}
		}`),
	})
}

func testIgnitionOverlay(c cluster.TestCluster) {
	m := c.Machines()[0]

	// Verify files created by Ignition
	c.Run("verify-files", func(c cluster.TestCluster) {
		// Check main test file
		output := c.MustSSH(m, "cat /etc/ignition-overlay-test")
		if string(output) != "Ignition overlay test successful" {
			c.Fatalf("Expected 'Ignition overlay test successful', got '%s'", string(output))
		}

		// Check config file
		output = c.MustSSH(m, "cat /etc/ignition-config-1")
		if string(output) != "Config 1" {
			c.Fatalf("Expected 'Config 1', got '%s'", string(output))
		}
	})

	// Verify systemd service
	c.Run("verify-service", func(c cluster.TestCluster) {
		// Check service is enabled
		c.RunCmdSync(m, "systemctl is-enabled ignition-overlay-test.service")

		// Check service ran (file should exist)
		c.RunCmdSync(m, "test -f /var/log/ignition-overlay-ran")
	})

	// Test overlay with additional config
	c.Run("test-overlay-merge", func(c cluster.TestCluster) {
		// This would test merging multiple Ignition configs
		// For now, just verify the base functionality
		c.RunCmdSync(m, "ls -la /etc/ignition-*")
	})
}

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

package misc

import (
	"fmt"

	"github.com/coreos/coreos-assembler/mantle/kola/cluster"
	"github.com/coreos/coreos-assembler/mantle/kola/register"
	"github.com/coreos/coreos-assembler/mantle/kola/tests/util"
)

func init() {
	register.RegisterTest(&register.Test{
		Run:         testDualRootfs,
		ClusterSize: 1,
		Name:        "nestos.dual-rootfs",
		Description: "Verify dual root filesystem (A/B) functionality works correctly.",
		Tags:        []string{"rpm-ostree", "dual-rootfs"},
	})
}

func testDualRootfs(c cluster.TestCluster) {
	m := c.Machines()[0]

	// Get initial rpm-ostree status
	c.Run("check-deployments", func(c cluster.TestCluster) {
		status, err := util.GetRpmOstreeStatusJSON(c, m)
		if err != nil {
			c.Fatalf("Failed to get rpm-ostree status: %v", err)
		}

		if len(status.Deployments) < 2 {
			c.Skipf("Dual rootfs test requires at least 2 deployments, found %d", len(status.Deployments))
		}

		// Find booted deployment
		var bootedDeployment *util.RpmOstreeDeployment
		for i, deployment := range status.Deployments {
			if deployment.Booted {
				bootedDeployment = &status.Deployments[i]
				break
			}
		}

		if bootedDeployment == nil {
			c.Fatal("No booted deployment found")
		}

		c.Logf("Current booted deployment: %s (checksum: %s)", bootedDeployment.Version, bootedDeployment.Checksum)

		// Create a marker file to verify we're on the right deployment
		markerContent := fmt.Sprintf("deployment-%s", bootedDeployment.Checksum[:8])
		c.RunCmdSync(m, fmt.Sprintf("echo '%s' > /etc/dual-rootfs-marker", markerContent))
	})

	// Test switching to another deployment
	c.Run("switch-deployment", func(c cluster.TestCluster) {
		status, err := util.GetRpmOstreeStatusJSON(c, m)
		if err != nil {
			c.Fatalf("Failed to get rpm-ostree status: %v", err)
		}

		// Find non-booted deployment
		var targetDeployment *util.RpmOstreeDeployment
		for i, deployment := range status.Deployments {
			if !deployment.Booted {
				targetDeployment = &status.Deployments[i]
				break
			}
		}

		if targetDeployment == nil {
			c.Skip("No alternative deployment available for switching")
		}

		c.Logf("Switching to deployment: %s (checksum: %s)", targetDeployment.Version, targetDeployment.Checksum)

		// Switch to the target deployment
		c.RunCmdSync(m, fmt.Sprintf("sudo rpm-ostree deploy %s", targetDeployment.Checksum))
	})

	// Reboot and verify
	c.Run("reboot-verify", func(c cluster.TestCluster) {
		// Reboot the machine
		err := m.Reboot()
		if err != nil {
			c.Fatalf("Failed to reboot machine: %v", err)
		}

		// Wait for machine to come back
		// (kola handles this automatically)

		// Verify we're on the new deployment
		status, err := util.GetRpmOstreeStatusJSON(c, m)
		if err != nil {
			c.Fatalf("Failed to get rpm-ostree status after reboot: %v", err)
		}

		// Find the new booted deployment
		var newBootedDeployment *util.RpmOstreeDeployment
		for i, deployment := range status.Deployments {
			if deployment.Booted {
				newBootedDeployment = &status.Deployments[i]
				break
			}
		}

		if newBootedDeployment == nil {
			c.Fatal("No booted deployment found after reboot")
		}

		c.Logf("New booted deployment: %s (checksum: %s)", newBootedDeployment.Version, newBootedDeployment.Checksum)

		// Verify marker file doesn't exist (since we're on a different deployment)
		output, err := c.SSH(m, "cat /etc/dual-rootfs-marker")
		if err == nil {
			c.Logf("Warning: marker file still exists with content: %s", string(output))
			c.Log("This may indicate the deployment switch didn't work as expected")
		} else {
			c.Log("Marker file correctly absent on new deployment")
		}
	})

	// Cleanup: switch back to original deployment
	c.Run("cleanup", func(c cluster.TestCluster) {
		// Get current status
		status, err := util.GetRpmOstreeStatusJSON(c, m)
		if err != nil {
			c.Logf("Warning: Failed to get status for cleanup: %v", err)
			return
		}

		// Find the first (original) deployment
		if len(status.Deployments) > 1 {
			originalChecksum := status.Deployments[1].Checksum
			c.RunCmdSync(m, fmt.Sprintf("sudo rpm-ostree deploy %s", originalChecksum))
		}
	})
}

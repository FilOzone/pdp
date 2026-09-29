"""Exercise announcement tooling with real ABI encoding and stubbed RPC/wallet calls."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "announce-planned-upgrade.sh"
PROXY = "0x1111111111111111111111111111111111111111"
IMPLEMENTATION = "0x2222222222222222222222222222222222222222"
OWNER = "0x3333333333333333333333333333333333333333"
SIGNATURE = "announceUpgradePlan(address,uint96)"

# Only calldata encoding invokes the real cast binary. All other calls are local
# fixtures, including send; these tests never contact an RPC or sign a transaction.
CAST_STUB = r'''
import json
import os
import sys

args = sys.argv[1:]
with open(os.environ["CAST_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args[0] == "calldata":
    os.execv(os.environ["REAL_CAST"], [os.environ["REAL_CAST"], *args])
elif args == ["chain-id"]:
    print("314")
elif args[0] == "call" and args[-1] == "nextUpgrade()(address,uint96)":
    print("0x0000000000000000000000000000000000000000\n0")
elif args[0] == "call" and args[-1] == "owner()(address)":
    print(os.environ["TEST_OWNER"])
elif args[0] == "call" and args[-1] == "nonce()(uint256)":
    print("12")
elif args[0] == "code":
    print("0x" if os.environ.get("EOA_OWNER") else "0x6000")
elif args[0:2] == ["wallet", "address"]:
    print(os.environ.get("TEST_SIGNER", os.environ["TEST_OWNER"]))
elif args[0] == "nonce":
    print("7")
elif args[0] == "send":
    print(json.dumps({"transactionHash": "0x" + "ab" * 32}))
else:
    sys.exit("Unexpected cast invocation: " + repr(args))
'''


class AnnouncementTests(unittest.TestCase):
    def setUp(self):
        real_cast = shutil.which("cast")
        self.assertIsNotNone(real_cast, "Foundry cast is required")
        self.assertIsNotNone(shutil.which("jq"), "jq is required")
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.log = self.root / "cast.log"
        stub = self.root / "cast"
        stub.write_text(f"#!{sys.executable}\n" + CAST_STUB)
        stub.chmod(0o755)
        # Isolate tests from the caller's RPC, wallet, and upgrade settings.
        self.env = {
            "PATH": str(self.root) + os.pathsep + os.environ["PATH"],
            "CAST_LOG": str(self.log),
            "REAL_CAST": real_cast,
            "TEST_OWNER": OWNER,
            "RPC_URL": "http://unused.invalid",
            "PDP_VERIFIER_PROXY_ADDRESS": PROXY,
            "NEW_PDP_VERIFIER_IMPLEMENTATION_ADDRESS": IMPLEMENTATION,
            "UPGRADE_DELAY_EPOCHS": "2880",
        }

    def run_script(self, **overrides):
        env = {**self.env, **overrides}
        env = {key: value for key, value in env.items() if value is not None}
        self.log.write_text("")
        result = subprocess.run(
            ["bash", str(SCRIPT)], env=env, text=True, capture_output=True, timeout=20
        )
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        return result, calls

    def assert_no_broadcast(self, calls):
        self.assertFalse(any(call[0] in ("send", "wallet") for call in calls), calls)

    def test_safe_prints_delay_calldata_without_wallet(self):
        result, calls = self.run_script(SAFE_ADDRESS=OWNER)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        expected = "0x7df6b5c3" + IMPLEMENTATION[2:].zfill(64) + format(2880, "064x")
        self.assertIn(f"target: {PROXY}", result.stdout)
        self.assertIn("value: 0", result.stdout)
        self.assertIn(f"data: {expected}", result.stdout)
        self.assertIn("owner nonce: 12", result.stdout)
        self.assertIn("Read nextUpgrade()", result.stdout)
        self.assertIn(["calldata", SIGNATURE, IMPLEMENTATION, "2880"], calls)
        self.assert_no_broadcast(calls)

    def test_rpc_alias_and_zero_delay(self):
        result, calls = self.run_script(
            RPC_URL=None, ETH_RPC_URL="http://unused.invalid", UPGRADE_DELAY_EPOCHS="0"
        )
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn(["calldata", SIGNATURE, IMPLEMENTATION, "0"], calls)
        self.assertIn("0x7df6b5c3" + IMPLEMENTATION[2:].zfill(64) + "0" * 64, result.stdout)
        self.assert_no_broadcast(calls)

    def test_missing_delay_fails_before_rpc(self):
        result, calls = self.run_script(UPGRADE_DELAY_EPOCHS=None)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("UPGRADE_DELAY_EPOCHS is not set", result.stdout)
        self.assertEqual(calls, [])

    def test_retired_epoch_fails_even_with_delay(self):
        for delay in (None, "2880"):
            with self.subTest(delay=delay):
                result, calls = self.run_script(AFTER_EPOCH="9999999", UPGRADE_DELAY_EPOCHS=delay)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("AFTER_EPOCH is no longer supported", result.stdout)
                self.assertEqual(calls, [])

    def test_invalid_delay_cannot_reach_broadcast(self):
        for delay in ("invalid", "-1", str(2**96)):
            with self.subTest(delay=delay):
                result, calls = self.run_script(UPGRADE_DELAY_EPOCHS=delay, EOA_OWNER="1")
                self.assertNotEqual(result.returncode, 0)
                self.assert_no_broadcast(calls)

    def test_safe_owner_mismatch_fails(self):
        result, calls = self.run_script(SAFE_ADDRESS=PROXY)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match proxy owner", result.stdout)
        self.assert_no_broadcast(calls)

    def test_eoa_broadcast_uses_relative_delay(self):
        result, calls = self.run_script(EOA_OWNER="1", KEYSTORE="unused", PASSWORD="unused")
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        sends = [call for call in calls if call[0] == "send"]
        self.assertEqual(sends, [[
            "send", "--keystore", "unused", "--password", "unused", PROXY,
            SIGNATURE, IMPLEMENTATION, "2880", "--nonce", "7", "--json",
        ]])
        self.assertIn("transaction sent: 0x" + "ab" * 32, result.stdout)
        self.assertIn("Read nextUpgrade()", result.stdout)

    def test_eoa_owner_mismatch_cannot_broadcast(self):
        result, calls = self.run_script(
            EOA_OWNER="1", KEYSTORE="unused", PASSWORD="unused", TEST_SIGNER=PROXY
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("is not the proxy owner", result.stdout)
        self.assertFalse(any(call[0] == "send" for call in calls))


if __name__ == "__main__":
    unittest.main()

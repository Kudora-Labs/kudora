# Kudora Mainnet Node — Quickstart Guide

This guide walks you from pulling the code to running a **Kudora** mainnet node. It includes brief explanations so you know _why_ each step matters.

> **Audience**: operators who are comfortable with a Linux terminal.
> **Goal**: build the `kudorad` binary, initialize a node home, load the mainnet genesis, validate it, and start the node.

---

## 1) Prerequisites

- A recent Linux distribution or macOS.
- Go toolchain installed (match the project’s required Go version).

---

## 2) Pull the code & build

```bash
# 2.1 Pull the source code
git clone https://github.com/Kudora-Labs/kudora.git
cd kudora

# 2.2 Build & install the binary into your $GOBIN (often ~/go/bin)
make install
```

### Verify the build

Make sure the `kudorad` binary is available and runnable:

```bash
which kudorad
kudorad version
```

If `which` prints a path and `kudorad version` prints version info, compilation succeeded.

> **Why this matters:** you need a working `kudorad` binary before you can initialize or run a node.

---

## 3) Create your node directory

Choose where your node’s data and configs will live. You can use an absolute path or a relative one. In this guide we’ll use a variable so the commands are easy to copy.

```bash
# Pick a directory for your node home
export NODE_HOME=./path-to-the-node-dir
mkdir -p "$NODE_HOME"
```

---

## 4) Initialize the node

Give your node a **Moniker** (a friendly name that shows up in peers lists) and set the **chain ID**.

```bash
# Replace <Moniker> with your node name (no spaces)
kudorad init <Moniker> \
  --chain-id kudora_12000-1 \
  --home "$NODE_HOME"
```

---

## 4.1) (Optional) Create a brand-new chain from scratch

> **Use this if you want to create your own local/test network instead of joining mainnet.**
> You’ll create a key, allocate tokens in the genesis, generate a validator gentx, and collect it into the genesis.

1. **Create a wallet/key (stored in the file keyring):**

```bash
kudorad keys add <WalletName> \
  --keyring-backend file \
  --home "$NODE_HOME"
```

_You’ll be prompted for a passphrase and shown a mnemonic (save it securely)._

2. **Allocate tokens to that wallet in genesis:**

```bash
kudorad genesis add-genesis-account <WalletName> <amount><denom> \
  --keyring-backend file \
  --home "$NODE_HOME"
```

- **Format:** `<amount><denom>` (no spaces), e.g., `100000000stake` or `50000000utoken`.
- Ensure **`<denom>`** matches your app’s configuration (the staking bond denom).

3. **Create a validator gentx (self-delegate some of your tokens):**

```bash
kudorad genesis gentx <WalletName> <amount><denom> \
  --chain-id kudora_12000-1 \
  --keyring-backend file \
  --home "$NODE_HOME"
```

4. **Collect gentxs into the genesis:**

```bash
kudorad genesis collect-gentxs --home "$NODE_HOME"
```

5. **Validate and start your brand-new chain:**
   Now skip to **Step 6 (Configure the client)**

> If you follow this optional path, **do not** perform Step 5 (downloading the mainnet genesis).

---

## 5) Load the mainnet genesis

> **Skip this step** if you followed **4.1 Optional** to create a chain from scratch.

Download the official `genesis.json` and place it into your node’s config directory.

```bash
# Fetch the pinned mainnet genesis
curl -L \
  -o "$NODE_HOME/config/genesis.json" \
  "https://raw.githubusercontent.com/Kudora-Labs/kud-network-mainnet/c66fd3fc25d8a2a8cae8125141dd8843ee0bf847/genesis.json"
```

> **Why this matters:** The genesis file is the canonical starting state for the blockchain. If the wrong file is used, your node will reject the network (or vice versa).

---

## 6) Configure the client (chain ID)

Depending on the CLI version, configuration can look like the following. Use **one** form that your binary supports:

```bash
kudorad config set client chain-id kudora_12000-1 --home "$NODE_HOME"
```

---

## 7) Validate the genesis

Before starting, validate the `genesis.json` to catch formatting or checksum issues early.

```bash
kudorad genesis validate-genesis --home "$NODE_HOME"
```

A successful validation prints no errors.

---

## 8) Start the node

```bash
kudorad start --home "$NODE_HOME"
```

You should see your node starting, loading the genesis, and beginning to sync.

> **Logs:** Keep this terminal open to watch logs. If you’re running in production, consider setting up a `systemd` service and a log rotation policy.

---

## What you achieved

- Built the `kudorad` binary.
- Initialized a node home with your moniker and chain ID.
- **EITHER** loaded the official mainnet `genesis.json` **OR** created a fresh chain from scratch.
- Validated the genesis and started your node.

You’re now running a Kudora node 🎉 From here, you can add seeds/peers, set pruning, or configure a service for production use.

---

## Quick Reference (copy/paste)

```bash
# Pull sources
git clone https://github.com/Kudora-Labs/kudora.git
cd kudora
make install

# Verify binary
which kudorad
kudorad version

# Node home
export NODE_HOME=./path-to-the-node-dir
mkdir -p "$NODE_HOME"

# Init (mainnet chain-id shown; change if you make a private chain)
kudorad init <Moniker> --chain-id kudora_12000-1 --home "$NODE_HOME"

# ===== Optional: Create a chain from scratch (local devnet) =====
# Wallet
kudorad keys add <WalletName> --keyring-backend file --home "$NODE_HOME"

# Allocate tokens in genesis
kudorad genesis add-genesis-account <WalletName> <amount><denom> \
  --keyring-backend file --home "$NODE_HOME"

# Create validator gentx (self-delegate)
kudorad genesis gentx <WalletName> <amount><denom> \
  --chain-id kudora_12000-1 --keyring-backend file --home "$NODE_HOME"

# Collect gentxs
kudorad genesis collect-gentxs --home "$NODE_HOME"
# =================================================================
# NOTE: Use the same <denom> as your staking bond denom.

# Mainnet genesis (skip if you created your own chain above)
curl -L -o "$NODE_HOME/config/genesis.json" \
  "https://raw.githubusercontent.com/Kudora-Labs/kud-network-mainnet/refs/heads/main/genesis.json"

# Configure client (optional but handy)
kudorad config set client chain-id kudora_12000-1 --home "$NODE_HOME"

# Validate & start
kudorad genesis validate-genesis --home "$NODE_HOME"
kudorad start --home "$NODE_HOME"
# Kudora — Quickstart Guide

> This guide offers two paths:
>
> - **Join the Kudora Mainnet.** Build `kudorad`, load the official `genesis.json`, and start syncing.
> - **Launch a Local Devnet (LocalNet).** Spin up a private, single-validator network on your machine/LAN using the same Kudora binary—ideal for testing.

---

## 1) Prerequisites

- Recent Linux distribution or macOS
- **Go 1.23** (required)
- Build tools: `make`, a C compiler (GCC or Clang), plus `git`, `curl`, `jq`
- Network access to fetch the code and `genesis.json`

### Install dependencies and Go

#### Linux (Ubuntu/Debian)
For ARM64, replace `amd64` with `arm64` in the Go download URL.

```bash
sudo apt update
sudo apt install -y build-essential make gcc git curl jq
curl -fsSLO https://go.dev/dl/go1.23.0.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.23.0.linux-amd64.tar.gz
rm -f go1.23.0.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
echo 'export GOPATH=$HOME/go; export PATH=$PATH:$GOPATH/bin' >> ~/.bashrc
source ~/.bashrc
go version
which go
```

#### MacOS

```bash
brew update
brew install make gcc git curl jq
brew install go
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc
echo 'export GOPATH=$HOME/go; export PATH=$PATH:$GOPATH/bin' >> ~/.zshrc
source ~/.zshrc
go version
which go
```

#### Windows

```bash
winget install --id Git.Git -e
winget install --id GNU.Make -e
winget install --id GCC.GCC -e
winget install --id Curl.Curl -e
winget install --id jqlang.jq -e
winget install --id GoLang.Go -e
---

After, add to your Path :
C:\Go\bin
%USERPROFILE%\go\bin

Finaly :
go version
which go
```

---

## 2) Pull the code & build

```bash
git clone https://github.com/Kudora-Labs/kudora.git
cd kudora
make install
which kudorad
kudorad version
```

---

## 3) Environment setup

```bash
export NODE_HOME="$HOME/.kudora"
export MONIKER="YOUR-MONIKER-NAME"
```

Choose **one** chain ID (Mainnet **or** LocalNet):

**Mainnet:**

```bash
export CHAIN_ID="kudora_12000-1"
```

**LocalNet:**

```bash
export CHAIN_ID="kudora-local-1"
```

---

## 4) Initialize the node

A moniker is your node’s public nickname.

```bash
kudorad init "$MONIKER" --chain-id "$CHAIN_ID" --home "$NODE_HOME"
```

---

## 5) Join the Kudora Mainnet

### 5.1 Set mainnet sources (pinned)

Do not change these; they pin network artifacts for reproducible setup.

```bash
export PINNED_COMMIT="a44ea19cbddf600fc8673b62acace42f32dd3ccf"
export BASE="https://raw.githubusercontent.com/Kudora-Labs/kud-network-mainnet/$PINNED_COMMIT"
export LISTS_URL="$BASE/networks/mainnet"
export CFG="$NODE_HOME/config/config.toml"
```

### 5.2 Get the mainnet genesis

**Option 1 — Pinned from GitHub (recommended):**

```bash
curl -fsSL "$BASE/genesis.json" -o "$NODE_HOME/config/genesis.json"
```

**Option 2 — From a live RPC you trust:**

```bash
export RPC="https://rpc.example.net:26657"
curl -fsSL "$RPC/genesis" | jq '.result.genesis // .genesis' > "$NODE_HOME/config/genesis.json"
```

### 5.3 Configure P2P

Bind the P2P listener and choose **one** profile below (Full Node **or** Validator):

```bash
sed -i -E 's|^laddr = ".*"|laddr = "tcp://0.0.0.0:26656"|' "$CFG"
```

**Full Node profile:**

```bash
MAX_SEEDS=3
MAX_PEERS=5
SEEDS=$(curl -fsSL "$LISTS_URL/seeds.txt"  | grep -vE '^\s*(#|$)' | shuf -n "$MAX_SEEDS" | paste -sd,)
PEERS=$(curl -fsSL "$LISTS_URL/peers.txt" | grep -vE '^\s*(#|$)' | shuf -n "$MAX_PEERS" | paste -sd,)
sed -i -E "s|^seeds = \".*\"|seeds = \"$SEEDS\"|" "$CFG"
sed -i -E "s|^persistent_peers = \".*\"|persistent_peers = \"$PEERS\"|" "$CFG"
sed -i -E 's|^pex = .*|pex = true|' "$CFG"
```

**Validator profile:**

```bash
SENTRY_PEERS="NODEID_A@SENTRY_A:26656,NODEID_B@SENTRY_B:26656"
SENTRY_IDS=$(printf "%s" "$SENTRY_PEERS" | tr ',' '\n' | cut -d@ -f1 | paste -sd,)
sed -i -E 's|^seeds = ".*"|seeds = ""|' "$CFG"
sed -i -E "s|^persistent_peers = \".*\"|persistent_peers = \"$SENTRY_PEERS\"|" "$CFG"
sed -i -E "s|^unconditional_peer_ids = \".*\"|unconditional_peer_ids = \"$SENTRY_IDS\"|" "$CFG"
sed -i -E 's|^pex = .*|pex = false|' "$CFG"
```

---

## 6) If You Choose Validator Profile Only

Set a wallet name once and reuse it everywhere.

```bash
export WALLET_NAME="YOUR-WALLET"
```

### 6.1 Put the wallet into the node’s keyring (choose one)

```bash
kudorad keys add "$WALLET_NAME" --keyring-backend file --home "$NODE_HOME"
```

```bash
kudorad keys add "$WALLET_NAME" --recover --keyring-backend file --home "$NODE_HOME"
```

```bash
kudorad keys import "$WALLET_NAME" ~/wallets/"$WALLET_NAME".txt --keyring-backend file --home "$NODE_HOME"
```

> Security tip: store the mnemonic offline and never share it.
> Fund **`$WALLET_NAME`** with enough tokens for **self-delegation** and **fees** before broadcasting.

### 6.2 Prepare & broadcast `create-validator`

`SELF_AMOUNT_KUD`: The self-delegation you bond now, written as an integer in base `kud`.

`MIN_SELF_KUD`: the minimum self-delegation your validator must always keep, as an integer in base kud; it cannot be lowered later, and if your self-delegation ever falls below this threshold the validator is jailed until you self-delegate back to at least `MIN_SELF_KUD` and then unjail; choose this value carefully because raising it later tightens your safety margin and you can’t roll it back. Written as an integer in base `kud`.

`IDENTITY / WEBSITE / SECURITY / DETAILS`: Optional public metadata displayed by explorers for your validator.

`COMMISSION_RATE`: the starting commission fraction you take from delegators’ rewards (e.g. `0.05` = 5%); it can change later but must stay ≤ `COMMISSION_MAX_RATE` and move by at most `COMMISSION_MAX_CHANGE_RATE` per 24h.

`COMMISSION_MAX_RATE`: the hard ceiling your commission can ever reach (e.g. `0.10` = 10%); it’s fixed at creation and cannot be raised later.

`COMMISSION_MAX_CHANGE_RATE`: the maximum amount you can change `COMMISSION_RATE` within a 24h window (e.g. `0.01` = up to ±1% per day); it’s set at creation and cannot be changed later.

`CONS_PUBKEY_B64`: The consensus ed25519 public key in base64, read automatically from your node home.

```bash
export SELF_AMOUNT_KUD="1000000000000000000"
export MIN_SELF_KUD="1000000000000000000"

export IDENTITY=""
export WEBSITE=""
export SECURITY=""
export DETAILS=""

export COMMISSION_RATE="0.05"
export COMMISSION_MAX_RATE="0.10"
export COMMISSION_MAX_CHANGE_RATE="0.01"

export CONS_PUBKEY_B64=$(
  kudorad tendermint show-validator --home "$NODE_HOME" 2>/dev/null \
  | jq -r '.key // .pub_key.key // .pubkey.key // .PubKey.value // .value'
)

cat > create-validator.json <<EOF
{
  "amount": "${SELF_AMOUNT_KUD}kud",
  "commission-max-change-rate": "${COMMISSION_MAX_CHANGE_RATE}",
  "commission-max-rate": "${COMMISSION_MAX_RATE}",
  "commission-rate": "${COMMISSION_RATE}",
  "details": "${DETAILS}",
  "identity": "${IDENTITY}",
  "min-self-delegation": "${MIN_SELF_KUD}",
  "moniker": "${MONIKER}",
  "pubkey": {
    "@type": "/cosmos.crypto.ed25519.PubKey",
    "key": "${CONS_PUBKEY_B64}"
  },
  "security": "${SECURITY}",
  "website": "${WEBSITE}"
}
EOF

export FEE_POLICY_URL="$BASE/networks/mainnet/fees/fee_policy.json"
export GAS_PRICE=$(curl -fsSL "$FEE_POLICY_URL" | jq -r '.recommended_min_gas_price.low')

kudorad tx staking create-validator ./create-validator.json \
  --from "$WALLET_NAME" \
  --keyring-backend file \
  --home "$NODE_HOME" \
  --chain-id "$CHAIN_ID" \
  --gas auto \
  --gas-adjustment 1.1 \
  --gas-prices "$GAS_PRICE"

rm -f ./create-validator.json
```

### 6.3 Verify validator status

By operator address:

```bash
VALOPER=$(kudorad keys show "$WALLET_NAME" --bech val -a --keyring-backend file --home "$NODE_HOME")
kudorad query staking validator "$VALOPER"
```

Check if you’re in the active Tendermint set right now:

```bash
CONS_ADDR=$(kudorad tendermint show-address --home "$NODE_HOME" 2>/dev/null || kudorad comet show-address --home "$NODE_HOME")
kudorad query tendermint-validator-set --home "$NODE_HOME" --chain-id kudora_12000-1 \
| jq -r '.validators[].address' | grep -q "$CONS_ADDR" \
&& echo "✅ In active set" || echo "⏳ Not in active set yet"
```

---

## 7) Launch a Local Devnet (LocalNet)

**Read first:** All amounts below are **in base units `kud` (integers)**.

- `GENESIS_AMOUNT`: Total tokens allocated to your wallet in genesis.
- `GENTX_AMOUNT`: Portion of those tokens self-delegated in your validator gentx (must be ≤ `GENESIS_AMOUNT`).
- `DENOM`: Base denom (here `kud`).

### 7.1 Set LocalNet parameters

```bash
export WALLET_NAME="YOUR-WALLET"
export DENOM="kud"
export GENESIS_AMOUNT="13000000000000000000000000"
export GENTX_AMOUNT="1000000000000000000"
export KEYRING_BACKEND="file"
```

### 7.2 Create the wallet for LocalNet

```bash
kudorad keys add "$WALLET_NAME" --keyring-backend "$KEYRING_BACKEND" --home "$NODE_HOME"
```

### 7.3 Allocate tokens in genesis

```bash
kudorad genesis add-genesis-account "$WALLET_NAME" "${GENESIS_AMOUNT}${DENOM}" --keyring-backend "$KEYRING_BACKEND" --home "$NODE_HOME"
```

### 7.4 Create a validator gentx (self-delegate)

```bash
kudorad genesis gentx "$WALLET_NAME" "${GENTX_AMOUNT}${DENOM}" --chain-id "$CHAIN_ID" --keyring-backend "$KEYRING_BACKEND" --home "$NODE_HOME"
```

### 7.5 Collect gentxs into genesis

```bash
kudorad genesis collect-gentxs --home "$NODE_HOME"
```

---

## 8) Configure the client

```bash
kudorad config set client chain-id "$CHAIN_ID" --home "$NODE_HOME"
```

---

## 9) Validate the genesis

```bash
kudorad genesis validate-genesis --home "$NODE_HOME"
```

---

## 10) Start the node

```bash
kudorad start --home "$NODE_HOME"
```

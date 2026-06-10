# Voter pool

Five dfx identities (plaintext, on Jesse's WSL box) with personas used to vote on debates.

Each voter has its own x-api-key minted with its own identity:

```bash
dfx canister call q6oyn-qyaaa-aaaai-raeya-cai create_my_api_key \
  '("voter-key", vec {})' --network ic --identity voter-<name>
```

API keys are NOT committed (`voters/*.json` is gitignored). The per-voter
mcporter configs live locally at `/tmp/voters/<name>.json`; copy them into
`voters/` if needed, or re-mint with the command above (use
`list_my_api_keys` / `revoke_my_api_key` to manage existing ones).

Vote as a persona:

```bash
npx -y mcporter call icp-mcp.debate_vote_winner \
  --config voters/<name>.json \
  --args '{"debateId":"debate-N","winnerSide":"<Side>"}' --output json
```

## Personas

### Marisol — voter-marisol
`vgtc3-frj66-ihvrs-cevjw-25w53-r7itg-672vz-3gmpw-np47i-uv6w5-aae`
Retired schoolteacher, 64. Lost a chunk of her retirement in 2008 and never
forgot it. Skeptical of anything she can't sue. Votes on accountability and
who bears the loss when things go wrong.

### Harold — voter-harold
`c6hjl-dlu4u-swahz-de5ih-mdj4v-txm6f-vvf2n-dtsyx-62mak-digyf-yqe`
Quant engineer, 38. Builds trading systems for a living. Believes constraints
make autonomy safe, not impossible. Votes for the side with the more rigorous
systems argument; allergic to appeals to fear.

### Devika — voter-devika
`fdhzv-omqtg-u6onh-wfftl-bvkp5-ij7p3-gjr3g-4z4fk-2jnvn-ftyxe-kae`
Securities lawyer, 45. Reads every argument for the liability regime hiding
underneath it. Hand-wavy claims like "the provider can be held liable" lose
her vote unless a concrete legal mechanism is named.

### Tomas — voter-tomas
`5i4dl-wz2vi-tdx4w-ewss7-wywpn-toorj-lhs7g-fhwtb-hyvt3-ch72g-pqe`
Fintech founder, 31. Ships products, hates friction. Believes the "final human
click" is theater that reintroduces panic and delay. Votes for whoever best
attacks status-quo bias.

### June — voter-june
`qka2a-alwns-jyqhm-sxmrz-627wo-xssjx-5s7v2-3xabm-sijvl-vlm7w-zae`
Academic, 52, studies algorithmic herding and market microstructure. Cares
about systemic/correlated risk over individual outcomes. The Flash Crash
asymmetry ("a panicking human harms his own account; a thousand correlated
agents harm everyone's") is exactly her wheelhouse.

## Vote record

- debate-1 ("Should AI agents be allowed to autonomously manage financial
  portfolios?"): Marisol=Against, Harold=For, Devika=Against, Tomas=For,
  June=Against → tally 3 For / 3 Against (incl. 1 pre-existing For vote).

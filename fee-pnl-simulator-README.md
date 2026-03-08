# Fee P&L Simulator (CSV Template)

File: `payment-kita.evm.smartcontract/fee-pnl-simulator-template.csv`

## Tujuan
Model cepat untuk menentukan fee per lane yang:
1. Menutup variable cost per tx (bridge + ops + risk buffer)
2. Mencapai target gross margin
3. Tetap dibatasi cap fee agar kompetitif

## Input Utama (ubah manual)
- `monthly_tx_volume`
- `avg_ticket_usd`
- `bridge_fee_usd_per_tx`
- `rpc_ops_usd_per_tx`
- `monitoring_ops_usd_per_tx`
- `support_risk_buffer_usd_per_tx`
- `target_gross_margin_pct`
- `floor_fee_usd`
- `cap_fee_pct`

## Output Kunci (auto formula)
- `recommended_fee_usd_per_tx`
- `recommended_fee_pct_of_amount`
- `expected_gross_margin_usd_per_tx`
- `expected_gross_margin_pct`
- `monthly_revenue_usd`
- `monthly_variable_cost_usd`
- `monthly_gross_profit_usd`

## Cara Pakai
1. Import CSV ke Google Sheets / Excel.
2. Isi data aktual per lane (biaya bridge real dari quote + biaya ops internal).
3. Review kolom `recommended_fee_pct_of_amount`.
4. Jika terlalu tinggi untuk pasar, turunkan target margin atau optimasi biaya lane.

## Rule of Thumb
- Retail lane: cap 1.5% - 2.0%
- Higher-cost lane: cap bisa 2.25% sementara
- Jika `recommended_fee_usd_per_tx == cap_fee_usd_per_tx`, lane sedang "cap-constrained" (margin target tidak tercapai)

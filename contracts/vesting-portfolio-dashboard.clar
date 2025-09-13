;; Vesting Portfolio Dashboard
;; Comprehensive portfolio analytics and insights for beneficiaries

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u500))
(define-constant ERR_BENEFICIARY_NOT_FOUND (err u501))
(define-constant ERR_INVALID_TIMEFRAME (err u502))
(define-constant ERR_NO_PORTFOLIO_DATA (err u503))

;; Data variables
(define-data-var dashboard-enabled bool true)
(define-data-var analytics-window-blocks uint u1008)
(define-data-var portfolio-update-interval uint u144)

;; Portfolio snapshot data
(define-map portfolio-snapshots
  { beneficiary: principal, snapshot-id: uint }
  {
    total-vested-value: uint,
    total-claimed-value: uint,
    performance-score: uint,
    contribution-score: uint,
    projected-next-claim: uint,
    portfolio-health: uint,
    snapshot-block: uint
  }
)

;; Portfolio alerts and notifications
(define-map portfolio-alerts
  principal
  {
    low-performance-warning: bool,
    claim-available-alert: bool,
    schedule-ending-alert: bool,
    decay-risk-warning: bool,
    last-alert-block: uint
  }
)

;; Portfolio performance metrics
(define-map portfolio-metrics
  principal
  {
    vesting-efficiency: uint,
    claim-frequency: uint,
    performance-trend: (string-ascii 15),
    risk-score: uint,
    diversification-score: uint,
    last-calculated: uint
  }
)

;; User portfolio preferences
(define-map portfolio-preferences
  principal
  {
    preferred-claim-frequency: uint,
    auto-optimization-enabled: bool,
    alert-threshold: uint,
    dashboard-theme: (string-ascii 10)
  }
)

;; Data counter
(define-data-var snapshot-counter uint u0)

;; Generate comprehensive portfolio summary
(define-public (generate-portfolio-summary (beneficiary principal))
  (let (
    (vesting-data (contract-call? .token-vesting get-vesting-schedule beneficiary))
    (performance-data (contract-call? .performance-vesting get-performance-summary beneficiary))
    (contribution-data (contract-call? .contribution-rewards get-contributor-stats beneficiary))
    (decay-status (contract-call? .performance-decay get-decay-status beneficiary))
  )
    (match vesting-data
      schedule
        (let (
          (total-vested (get total-amount schedule))
          (claimed-amount (get tokens-claimed schedule))
          (remaining-amount (- total-vested claimed-amount))
          (completion-percentage (/ (* claimed-amount u100) total-vested))
          (claimable-now (unwrap-panic (contract-call? .token-vesting get-claimable-tokens beneficiary)))
        )
          (ok {
            portfolio-value: {
              total-allocated: total-vested,
              total-claimed: claimed-amount,
              remaining-balance: remaining-amount,
              claimable-now: claimable-now,
              completion-percentage: completion-percentage
            },
            performance-metrics: performance-data,
            contribution-metrics: contribution-data,
            decay-metrics: decay-status,
            portfolio-health: (calculate-portfolio-health beneficiary total-vested claimed-amount),
            last-updated: stacks-block-height
          })
        )
      (err u0)
    )
  )
)

;; Calculate portfolio health score
(define-private (calculate-portfolio-health (beneficiary principal) (total-vested uint) (claimed-amount uint))
  (let (
    (claim-ratio (/ (* claimed-amount u100) total-vested))
    (performance-bonus (get-performance-bonus beneficiary))
    ;; (decay-penalty (get-decay-penalty beneficiary))
    (base-health (+ claim-ratio performance-bonus))
    (final-health (if (> base-health u200) (- base-health u200) u0))
  )
    (if (> final-health u100) u100 final-health)
  )
)

;; Get performance bonus for health calculation
(define-private (get-performance-bonus (beneficiary principal))
  (match (contract-call? .performance-vesting get-performance-score beneficiary)
    performance-data (/ (get current-score performance-data) u4)
    u0
  )
)

;; Get decay penalty for health calculation
;; (define-private (get-decay-penalty (beneficiary principal))
;;   (match (contract-call? .performance-decay get-decay-status beneficiary)
;;     ok decay-data (min (get pending-decay decay-data) u25)
;;     err err-val u0))

;; Create portfolio snapshot
(define-public (create-portfolio-snapshot (beneficiary principal))
  (let (
    (snapshot-id (+ (var-get snapshot-counter) u1))
    (portfolio-summary (unwrap! (generate-portfolio-summary beneficiary) ERR_NO_PORTFOLIO_DATA))
    (portfolio-value (get portfolio-value portfolio-summary))
  )
    (map-set portfolio-snapshots
      { beneficiary: beneficiary, snapshot-id: snapshot-id }
      {
        total-vested-value: (get total-allocated portfolio-value),
        total-claimed-value: (get total-claimed portfolio-value),
        performance-score: u100,
        contribution-score: u100,
        projected-next-claim: (calculate-next-claim-projection beneficiary),
        portfolio-health: (get portfolio-health portfolio-summary),
        snapshot-block: stacks-block-height
      }
    )
    (var-set snapshot-counter snapshot-id)
    (ok snapshot-id)
  )
)

;; Calculate projected next claim amount
(define-private (calculate-next-claim-projection (beneficiary principal))
  (let (
    (claimable-now (unwrap-panic (contract-call? .token-vesting get-claimable-tokens beneficiary)))
    (analytics-window (var-get analytics-window-blocks))
    (projected-future-claim (/ claimable-now u2))
  )
    (+ claimable-now projected-future-claim)
  )
)

;; Update portfolio alerts
(define-public (update-portfolio-alerts (beneficiary principal))
  (let (
    (portfolio-summary (unwrap! (generate-portfolio-summary beneficiary) ERR_NO_PORTFOLIO_DATA))
    (portfolio-health (get portfolio-health portfolio-summary))
    (claimable-amount (get claimable-now (get portfolio-value portfolio-summary)))
    (decay-risk (check-decay-risk beneficiary))
  )
    (map-set portfolio-alerts beneficiary {
      low-performance-warning: (< portfolio-health u30),
      claim-available-alert: (> claimable-amount u0),
      schedule-ending-alert: (check-schedule-ending-soon beneficiary),
      decay-risk-warning: decay-risk,
      last-alert-block: stacks-block-height
    })
    (ok true)
  )
)

;; Check if decay risk is present
(define-private (check-decay-risk (beneficiary principal))
  ;; (match (contract-call? .performance-decay get-decay-status beneficiary)
  ;;   ok decay-data (> (get pending-decay decay-data) u10)
  ;;   err err-val false
  ;; )
  false ;; Placeholder until decay contract is implemented
)

;; Check if vesting schedule is ending soon
(define-private (check-schedule-ending-soon (beneficiary principal))
  false ;; Placeholder until vesting contract is implemented
)

;; Calculate portfolio efficiency metrics
(define-public (calculate-portfolio-efficiency (beneficiary principal))
  (let (
    (portfolio-summary (unwrap! (generate-portfolio-summary beneficiary) ERR_NO_PORTFOLIO_DATA))
    (portfolio-value (get portfolio-value portfolio-summary))
    (total-allocated (get total-allocated portfolio-value))
    (total-claimed (get total-claimed portfolio-value))
    (claim-efficiency (if (> total-allocated u0) (/ (* total-claimed u100) total-allocated) u0))
    (performance-multiplier (get-current-performance-multiplier beneficiary))
    (vesting-velocity (calculate-vesting-velocity beneficiary))
  )
    (map-set portfolio-metrics beneficiary {
      vesting-efficiency: claim-efficiency,
      claim-frequency: vesting-velocity,
      performance-trend: (determine-performance-trend beneficiary),
      risk-score: (calculate-risk-score beneficiary),
      diversification-score: u75,
      last-calculated: stacks-block-height
    })
    (ok {
      efficiency: claim-efficiency,
      velocity: vesting-velocity,
      multiplier: performance-multiplier,
      risk-level: (calculate-risk-score beneficiary)
    })
  )
)

;; Get current performance multiplier
(define-private (get-current-performance-multiplier (beneficiary principal))
  (match (contract-call? .performance-vesting get-performance-score beneficiary)
    performance-data (get current-score performance-data)
    u100
  )
)

;; Calculate vesting velocity (claims per period)
(define-private (calculate-vesting-velocity (beneficiary principal))
  u0
)

;; Determine performance trend
(define-private (determine-performance-trend (beneficiary principal))
  "stable"
)

;; Calculate risk score
(define-private (calculate-risk-score (beneficiary principal))
  (let (
    (decay-risk (if (check-decay-risk beneficiary) u30 u0))
    (performance-risk (get-performance-risk beneficiary))
    (schedule-risk (if (check-schedule-ending-soon beneficiary) u20 u0))
    (total-risk (+ decay-risk (+ performance-risk schedule-risk)))
  )
    (min total-risk u100)
  )
)

;; Get performance-based risk
(define-private (get-performance-risk (beneficiary principal))
  (let (
    (performance-multiplier (get-current-performance-multiplier beneficiary))
  )
    (if (< performance-multiplier u80) u25 u0)
  )
)

;; Set portfolio preferences
(define-public (set-portfolio-preferences 
  (claim-frequency uint)
  (auto-optimization bool)
  (alert-threshold uint)
  (theme (string-ascii 10)))
  (begin
    (asserts! (and (>= claim-frequency u1) (<= claim-frequency u52)) ERR_INVALID_TIMEFRAME)
    (asserts! (and (>= alert-threshold u1) (<= alert-threshold u100)) ERR_INVALID_TIMEFRAME)
    (map-set portfolio-preferences tx-sender {
      preferred-claim-frequency: claim-frequency,
      auto-optimization-enabled: auto-optimization,
      alert-threshold: alert-threshold,
      dashboard-theme: theme
    })
    (ok true)
  )
)

;; Get portfolio optimization recommendations
(define-read-only (get-optimization-recommendations (beneficiary principal))
  (let (
    (portfolio-summary (unwrap-panic (generate-portfolio-summary beneficiary)))
    (portfolio-health (get portfolio-health portfolio-summary))
    (claimable-amount (get claimable-now (get portfolio-value portfolio-summary)))
    (performance-multiplier (get-current-performance-multiplier beneficiary))
  )
    (ok {
      should-claim-now: (> claimable-amount u0),
      performance-action: (if (< performance-multiplier u90) "improve-performance" "maintain-performance"),
      risk-mitigation: (if (> (calculate-risk-score beneficiary) u50) "high-risk-review" "normal-monitoring"),
      optimal-claim-timing: (+ stacks-block-height u144),
      portfolio-health-status: (if (> portfolio-health u70) "healthy" "needs-attention")
    })
  )
)

;; Read-only functions
(define-read-only (get-portfolio-snapshot (beneficiary principal) (snapshot-id uint))
  (map-get? portfolio-snapshots { beneficiary: beneficiary, snapshot-id: snapshot-id })
)

(define-read-only (get-portfolio-alerts (beneficiary principal))
  (map-get? portfolio-alerts beneficiary)
)

(define-read-only (get-portfolio-metrics (beneficiary principal))
  (map-get? portfolio-metrics beneficiary)
)

(define-read-only (get-portfolio-preferences (beneficiary principal))
  (map-get? portfolio-preferences beneficiary)
)

(define-read-only (get-portfolio-overview (beneficiary principal))
  (match (generate-portfolio-summary beneficiary)
    summary
      (let (
        (alerts (default-to 
          { low-performance-warning: false, claim-available-alert: false, schedule-ending-alert: false, decay-risk-warning: false, last-alert-block: u0 }
          (map-get? portfolio-alerts beneficiary)))
        (metrics (default-to
          { vesting-efficiency: u0, claim-frequency: u0, performance-trend: "unknown", risk-score: u0, diversification-score: u0, last-calculated: u0 }
          (map-get? portfolio-metrics beneficiary)))
        (preferences (default-to
          { preferred-claim-frequency: u4, auto-optimization-enabled: false, alert-threshold: u50, dashboard-theme: "default" }
          (map-get? portfolio-preferences beneficiary)))
      )
        (ok {
          summary: summary,
          alerts: alerts,
          metrics: metrics,
          preferences: preferences,
          recommendations: (unwrap-panic (get-optimization-recommendations beneficiary))
        })
      )
    error-value (err error-value)
  )
)

;; Administrative functions
(define-public (toggle-dashboard (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (var-set dashboard-enabled enabled)
    (ok enabled)
  )
)

(define-public (update-analytics-parameters (window-blocks uint) (update-interval uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (and (>= window-blocks u144) (<= window-blocks u4032)) ERR_INVALID_TIMEFRAME)
    (asserts! (and (>= update-interval u24) (<= update-interval u1008)) ERR_INVALID_TIMEFRAME)
    (var-set analytics-window-blocks window-blocks)
    (var-set portfolio-update-interval update-interval)
    (ok true)
  )
)

;; Bulk portfolio updates for multiple beneficiaries
(define-public (bulk-update-portfolios (beneficiaries (list 20 principal)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (ok (map process-portfolio-update beneficiaries))
  )
)

;; Process individual portfolio update
(define-private (process-portfolio-update (beneficiary principal))
  (begin
    (unwrap-panic (update-portfolio-alerts beneficiary))
    (unwrap-panic (calculate-portfolio-efficiency beneficiary))
    (unwrap-panic (create-portfolio-snapshot beneficiary))
    true
  )
)

;; Get dashboard status
(define-read-only (get-dashboard-status)
  (ok {
    enabled: (var-get dashboard-enabled),
    analytics-window: (var-get analytics-window-blocks),
    update-interval: (var-get portfolio-update-interval),
    total-snapshots: (var-get snapshot-counter)
  })
)

;; Helper function for min calculation
(define-private (min (a uint) (b uint))
  (if (< a b) a b)
)




(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-SCORE (err u201))
(define-constant ERR-NO-PERFORMANCE-DATA (err u202))
(define-constant ERR-INVALID-MULTIPLIER (err u203))

(define-data-var contract-owner principal tx-sender)
(define-data-var base-performance-score uint u100)
(define-data-var max-performance-multiplier uint u200)
(define-data-var min-performance-multiplier uint u50)

(define-map performance-scores
    principal
    {
        current-score: uint,
        last-updated: uint,
        score-history: (list 12 uint),
        performance-multiplier: uint
    }
)

(define-map performance-metrics
    principal
    {
        total-evaluations: uint,
        average-score: uint,
        best-score: uint,
        worst-score: uint,
        trend-direction: (string-ascii 10)
    }
)

(define-map performance-thresholds
    (string-ascii 20)
    {
        min-score: uint,
        max-score: uint,
        vesting-multiplier: uint,
        bonus-percentage: uint
    }
)

(define-public (set-performance-score 
    (beneficiary principal)
    (score uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= score u0) (<= score u200)) ERR-INVALID-SCORE)
        (let (
            (current-data (default-to 
                {
                    current-score: (var-get base-performance-score),
                    last-updated: u0,
                    score-history: (list),
                    performance-multiplier: u100
                }
                (map-get? performance-scores beneficiary)))
            (new-history (unwrap-panic (as-max-len? 
                (append (get score-history current-data) score) u12)))
            (multiplier (calculate-performance-multiplier score))
        )
            (map-set performance-scores beneficiary {
                current-score: score,
                last-updated: stacks-block-height,
                score-history: new-history,
                performance-multiplier: multiplier
            })
            (update-performance-metrics beneficiary score)
            (ok multiplier)
        )
    )
)

(define-private (calculate-performance-multiplier (score uint))
    (let (
        (base-score (var-get base-performance-score))
        (max-multiplier (var-get max-performance-multiplier))
        (min-multiplier (var-get min-performance-multiplier))
    )
        (if (>= score base-score)
            (min max-multiplier (+ u100 (/ (* (- score base-score) u100) base-score)))
            (max min-multiplier (- u100 (/ (* (- base-score score) u50) base-score)))
        )
    )
)

(define-private (min (a uint) (b uint))
    (if (< a b) a b)
)

(define-private (max (a uint) (b uint))
    (if (> a b) a b)
)

(define-private (update-performance-metrics (beneficiary principal) (new-score uint))
    (let (
        (current-metrics (default-to
            {
                total-evaluations: u0,
                average-score: u100,
                best-score: u0,
                worst-score: u200,
                trend-direction: "stable"
            }
            (map-get? performance-metrics beneficiary)))
        (total-evals (+ (get total-evaluations current-metrics) u1))
        (new-average (/ (+ (* (get average-score current-metrics) (get total-evaluations current-metrics)) new-score) total-evals))
        (new-best (max (get best-score current-metrics) new-score))
        (new-worst (min (get worst-score current-metrics) new-score))
        (trend (if (> new-score (get average-score current-metrics)) "improving" "declining"))
    )
        (map-set performance-metrics beneficiary {
            total-evaluations: total-evals,
            average-score: new-average,
            best-score: new-best,
            worst-score: new-worst,
            trend-direction: trend
        })
    )
)

(define-public (calculate-performance-adjusted-vesting 
    (beneficiary principal)
    (base-vested-amount uint))
    (match (map-get? performance-scores beneficiary)
        performance-data
            (let (
                (multiplier (get performance-multiplier performance-data))
                (adjusted-amount (/ (* base-vested-amount multiplier) u100))
            )
                (ok adjusted-amount)
            )
        (ok base-vested-amount)
    )
)

(define-public (set-performance-threshold
    (threshold-name (string-ascii 20))
    (min-score uint)
    (max-score uint)
    (vesting-multiplier uint)
    (bonus-percentage uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (< min-score max-score) ERR-INVALID-SCORE)
        (asserts! (and (>= vesting-multiplier u50) (<= vesting-multiplier u300)) ERR-INVALID-MULTIPLIER)
        (ok (map-set performance-thresholds threshold-name {
            min-score: min-score,
            max-score: max-score,
            vesting-multiplier: vesting-multiplier,
            bonus-percentage: bonus-percentage
        }))
    )
)

(define-public (apply-performance-bonus 
    (beneficiary principal)
    (threshold-name (string-ascii 20)))
    (match (map-get? performance-scores beneficiary)
        performance-data
            (match (map-get? performance-thresholds threshold-name)
                threshold
                    (let (
                        (current-score (get current-score performance-data))
                        (min-score (get min-score threshold))
                        (max-score (get max-score threshold))
                    )
                        (if (and (>= current-score min-score) (<= current-score max-score))
                            (ok (get bonus-percentage threshold))
                            (ok u0)
                        )
                    )
                ERR-NO-PERFORMANCE-DATA
            )
        ERR-NO-PERFORMANCE-DATA
    )
)

(define-read-only (get-performance-score (beneficiary principal))
    (map-get? performance-scores beneficiary)
)

(define-read-only (get-performance-metrics (beneficiary principal))
    (map-get? performance-metrics beneficiary)
)

(define-read-only (get-performance-summary (beneficiary principal))
    (match (map-get? performance-scores beneficiary)
        performance-data
            (match (map-get? performance-metrics beneficiary)
                metrics
                    (ok {
                        current-score: (get current-score performance-data),
                        performance-multiplier: (get performance-multiplier performance-data),
                        average-score: (get average-score metrics),
                        total-evaluations: (get total-evaluations metrics),
                        trend: (get trend-direction metrics),
                        last-updated: (get last-updated performance-data)
                    })
                ERR-NO-PERFORMANCE-DATA
            )
        ERR-NO-PERFORMANCE-DATA
    )
)

(define-public (bulk-update-performance-scores 
    (updates (list 50 {beneficiary: principal, score: uint})))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (fold process-performance-update updates u0))
    )
)

(define-private (process-performance-update 
    (update {beneficiary: principal, score: uint})
    (counter uint))
    (begin
        (unwrap-panic (set-performance-score 
            (get beneficiary update) 
            (get score update)))
        (+ counter u1)
    )
)

(define-public (reset-performance-data (beneficiary principal))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (map-delete performance-scores beneficiary)
        (map-delete performance-metrics beneficiary)
        (ok true)
    )
)

(define-public (set-performance-parameters
    (base-score uint)
    (max-multiplier uint)
    (min-multiplier uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (> base-score u0) (<= base-score u200)) ERR-INVALID-SCORE)
        (asserts! (and (>= max-multiplier u100) (<= max-multiplier u500)) ERR-INVALID-MULTIPLIER)
        (asserts! (and (>= min-multiplier u10) (<= min-multiplier u100)) ERR-INVALID-MULTIPLIER)
        (var-set base-performance-score base-score)
        (var-set max-performance-multiplier max-multiplier)
        (var-set min-performance-multiplier min-multiplier)
        (ok true)
    )
)

(define-read-only (get-performance-parameters)
    (ok {
        base-score: (var-get base-performance-score),
        max-multiplier: (var-get max-performance-multiplier),
        min-multiplier: (var-get min-performance-multiplier)
    })
)
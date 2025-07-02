(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-INVALID-DECAY-RATE (err u301))
(define-constant ERR-NO-DECAY-DATA (err u302))
(define-constant ERR-INVALID-PERIOD (err u303))

(define-data-var contract-owner principal tx-sender)
(define-data-var global-decay-rate uint u5)
(define-data-var decay-period-blocks uint u1008)
(define-data-var minimum-score-floor uint u20)

(define-map decay-settings
    principal
    {
        custom-decay-rate: uint,
        last-decay-applied: uint,
        decay-immunity-until: uint,
        total-decay-applied: uint
    }
)

(define-map decay-history
    principal
    {
        decay-events: (list 24 {block-height: uint, decay-amount: uint, score-before: uint, score-after: uint}),
        total-periods-decayed: uint,
        average-decay-per-period: uint
    }
)

(define-public (calculate-current-decay (beneficiary principal))
    (let (
        (current-block stacks-block-height)
        (decay-data (default-to
            {
                custom-decay-rate: (var-get global-decay-rate),
                last-decay-applied: current-block,
                decay-immunity-until: u0,
                total-decay-applied: u0
            }
            (map-get? decay-settings beneficiary)))
        (blocks-since-decay (- current-block (get last-decay-applied decay-data)))
        (decay-periods (/ blocks-since-decay (var-get decay-period-blocks)))
        (immunity-until (get decay-immunity-until decay-data))
    )
        (if (or (< decay-periods u1) (> immunity-until current-block))
            (ok u0)
            (let (
                (decay-rate (get custom-decay-rate decay-data))
                (total-decay (* decay-periods decay-rate))
            )
                (ok total-decay)
            )
        )
    )
)

(define-public (apply-performance-decay (beneficiary principal) (current-score uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (let (
            (decay-amount (unwrap! (calculate-current-decay beneficiary) ERR-NO-DECAY-DATA))
        )
            (if (is-eq decay-amount u0)
                (ok current-score)
                (let (
                    (min-floor (var-get minimum-score-floor))
                    (decayed-score (max min-floor (- current-score decay-amount)))
                    (actual-decay (- current-score decayed-score))
                    (current-block stacks-block-height)
                )
                    (update-decay-settings beneficiary actual-decay)
                    (record-decay-event beneficiary current-score decayed-score actual-decay)
                    (ok decayed-score)
                )
            )
        )
    )
)

(define-private (update-decay-settings (beneficiary principal) (decay-applied uint))
    (let (
        (current-data (default-to
            {
                custom-decay-rate: (var-get global-decay-rate),
                last-decay-applied: u0,
                decay-immunity-until: u0,
                total-decay-applied: u0
            }
            (map-get? decay-settings beneficiary)))
        (new-total-decay (+ (get total-decay-applied current-data) decay-applied))
    )
        (map-set decay-settings beneficiary {
            custom-decay-rate: (get custom-decay-rate current-data),
            last-decay-applied: stacks-block-height,
            decay-immunity-until: (get decay-immunity-until current-data),
            total-decay-applied: new-total-decay
        })
    )
)

(define-private (record-decay-event 
    (beneficiary principal) 
    (score-before uint) 
    (score-after uint) 
    (decay-amount uint))
    (let (
        (current-history (default-to
            {
                decay-events: (list),
                total-periods-decayed: u0,
                average-decay-per-period: u0
            }
            (map-get? decay-history beneficiary)))
        (new-event {
            block-height: stacks-block-height,
            decay-amount: decay-amount,
            score-before: score-before,
            score-after: score-after
        })
        (updated-events (unwrap-panic (as-max-len? 
            (append (get decay-events current-history) new-event) u24)))
        (new-period-count (+ (get total-periods-decayed current-history) u1))
        (new-average (/ (+ (* (get average-decay-per-period current-history) 
                             (get total-periods-decayed current-history)) 
                          decay-amount) 
                       new-period-count))
    )
        (map-set decay-history beneficiary {
            decay-events: updated-events,
            total-periods-decayed: new-period-count,
            average-decay-per-period: new-average
        })
    )
)

(define-public (set-custom-decay-rate (beneficiary principal) (decay-rate uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= decay-rate u1) (<= decay-rate u20)) ERR-INVALID-DECAY-RATE)
        (let (
            (current-data (default-to
                {
                    custom-decay-rate: (var-get global-decay-rate),
                    last-decay-applied: stacks-block-height,
                    decay-immunity-until: u0,
                    total-decay-applied: u0
                }
                (map-get? decay-settings beneficiary)))
        )
            (ok (map-set decay-settings beneficiary {
                custom-decay-rate: decay-rate,
                last-decay-applied: (get last-decay-applied current-data),
                decay-immunity-until: (get decay-immunity-until current-data),
                total-decay-applied: (get total-decay-applied current-data)
            }))
        )
    )
)

(define-public (grant-decay-immunity (beneficiary principal) (immunity-blocks uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (> immunity-blocks u0) (<= immunity-blocks u4032)) ERR-INVALID-PERIOD)
        (let (
            (current-data (default-to
                {
                    custom-decay-rate: (var-get global-decay-rate),
                    last-decay-applied: stacks-block-height,
                    decay-immunity-until: u0,
                    total-decay-applied: u0
                }
                (map-get? decay-settings beneficiary)))
            (immunity-until (+ stacks-block-height immunity-blocks))
        )
            (ok (map-set decay-settings beneficiary {
                custom-decay-rate: (get custom-decay-rate current-data),
                last-decay-applied: (get last-decay-applied current-data),
                decay-immunity-until: immunity-until,
                total-decay-applied: (get total-decay-applied current-data)
            }))
        )
    )
)

(define-public (bulk-apply-decay (beneficiaries (list 25 principal)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (map process-beneficiary-decay beneficiaries))
    )
)

(define-private (process-beneficiary-decay (beneficiary principal))
    (unwrap-panic (calculate-current-decay beneficiary))
)

(define-public (set-global-decay-parameters
    (decay-rate uint)
    (period-blocks uint)
    (score-floor uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= decay-rate u1) (<= decay-rate u15)) ERR-INVALID-DECAY-RATE)
        (asserts! (and (>= period-blocks u144) (<= period-blocks u4032)) ERR-INVALID-PERIOD)
        (asserts! (and (>= score-floor u10) (<= score-floor u50)) ERR-INVALID-DECAY-RATE)
        (var-set global-decay-rate decay-rate)
        (var-set decay-period-blocks period-blocks)
        (var-set minimum-score-floor score-floor)
        (ok true)
    )
)

(define-read-only (get-decay-status (beneficiary principal))
    (match (map-get? decay-settings beneficiary)
        decay-data
            (let ((pending-decay (unwrap-panic (calculate-current-decay beneficiary))))
                (ok {
                    custom-decay-rate: (get custom-decay-rate decay-data),
                    last-decay-applied: (get last-decay-applied decay-data),
                    decay-immunity-until: (get decay-immunity-until decay-data),
                    total-decay-applied: (get total-decay-applied decay-data),
                    pending-decay: pending-decay,
                    blocks-until-next-decay: (- (var-get decay-period-blocks) 
                                               (mod (- stacks-block-height (get last-decay-applied decay-data)) 
                                                    (var-get decay-period-blocks)))
                })
            )
        ERR-NO-DECAY-DATA
    )
)

(define-read-only (get-decay-history (beneficiary principal))
    (map-get? decay-history beneficiary)
)

(define-read-only (get-global-decay-parameters)
    (ok {
        global-decay-rate: (var-get global-decay-rate),
        decay-period-blocks: (var-get decay-period-blocks),
        minimum-score-floor: (var-get minimum-score-floor)
    })
)

(define-private (max (a uint) (b uint))
    (if (> a b) a b)
)
;; Title: Dynamic Contribution Rewards System
;; Description: Tracks and rewards ongoing contributions with dynamic bonus allocations

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-CONTRIBUTION (err u401))
(define-constant ERR-INSUFFICIENT-REWARD-POOL (err u402))
(define-constant ERR-INVALID-WEIGHT (err u403))
(define-constant ERR-CONTRIBUTION-NOT-FOUND (err u404))
(define-constant ERR-INVALID-MULTIPLIER (err u405))
(define-constant ERR-REWARD-ALREADY-CLAIMED (err u406))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-reward-pool uint u1000000)
(define-data-var available-reward-pool uint u1000000)
(define-data-var contribution-window-blocks uint u1008)
(define-data-var min-contribution-score uint u10)
(define-data-var reward-distribution-interval uint u144)
(define-data-var last-distribution-block uint u0)

;; Contribution categories with different weights
(define-map contribution-categories
    (string-ascii 20)
    {
        base-weight: uint,
        max-daily-score: uint,
        decay-rate: uint,
        bonus-multiplier: uint
    }
)

;; Individual contribution records
(define-map contributor-records
    principal
    {
        total-contribution-score: uint,
        last-contribution-block: uint,
        active-streak-days: uint,
        lifetime-contributions: uint,
        category-scores: (list 10 {category: (string-ascii 20), score: uint, last-updated: uint})
    }
)

;; Daily contribution tracking
(define-map daily-contributions
    {contributor: principal, day-block: uint}
    {
        total-daily-score: uint,
        contributions: (list 20 {category: (string-ascii 20), score: uint, timestamp: uint}),
        multiplier-applied: uint
    }
)

;; Reward distribution tracking
(define-map reward-distributions
    {contributor: principal, distribution-period: uint}
    {
        reward-amount: uint,
        contribution-rank: uint,
        bonus-percentage: uint,
        claimed: bool,
        distribution-block: uint
    }
)

;; Contribution validation rules
(define-map contribution-validators
    (string-ascii 20)
    {
        min-score: uint,
        max-score: uint,
        requires-verification: bool,
        cooldown-blocks: uint
    }
)

;; Team-based contribution pools
(define-map team-contribution-pools
    (string-ascii 25)
    {
        team-members: (list 20 principal),
        pool-allocation: uint,
        distribution-method: (string-ascii 15),
        last-distribution: uint
    }
)

;; Initialize default contribution categories
(define-public (initialize-default-categories)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (try! (set-contribution-category "code-commits" u100 u500 u5 u120))
        (try! (set-contribution-category "bug-fixes" u150 u300 u3 u140))
        (try! (set-contribution-category "documentation" u80 u200 u4 u110))
        (try! (set-contribution-category "code-review" u120 u400 u4 u125))
        (try! (set-contribution-category "mentoring" u200 u250 u2 u160))
        (ok true)
    )
)

;; Set contribution category parameters
(define-public (set-contribution-category 
    (category (string-ascii 20))
    (base-weight uint)
    (max-daily-score uint)
    (decay-rate uint)
    (bonus-multiplier uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (> base-weight u0) (<= base-weight u500)) ERR-INVALID-WEIGHT)
        (asserts! (and (> max-daily-score u0) (<= max-daily-score u1000)) ERR-INVALID-CONTRIBUTION)
        (asserts! (and (>= decay-rate u1) (<= decay-rate u20)) ERR-INVALID-CONTRIBUTION)
        (asserts! (and (>= bonus-multiplier u100) (<= bonus-multiplier u300)) ERR-INVALID-MULTIPLIER)
        (ok (map-set contribution-categories category {
            base-weight: base-weight,
            max-daily-score: max-daily-score,
            decay-rate: decay-rate,
            bonus-multiplier: bonus-multiplier
        }))
    )
)

;; Record a new contribution
(define-public (record-contribution
    (contributor principal)
    (category (string-ascii 20))
    (contribution-score uint)
    (verification-data (optional (string-ascii 100))))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (>= contribution-score (var-get min-contribution-score)) ERR-INVALID-CONTRIBUTION)
        (let (
            (category-data (unwrap! (map-get? contribution-categories category) ERR-CONTRIBUTION-NOT-FOUND))
            (current-day-block (get-day-block stacks-block-height))
            (current-record (default-to
                {
                    total-contribution-score: u0,
                    last-contribution-block: u0,
                    active-streak-days: u0,
                    lifetime-contributions: u0,
                    category-scores: (list)
                }
                (map-get? contributor-records contributor)))
            (daily-data (default-to
                {
                    total-daily-score: u0,
                    contributions: (list),
                    multiplier-applied: u100
                }
                (map-get? daily-contributions {contributor: contributor, day-block: current-day-block})))
            (adjusted-score (min contribution-score (get max-daily-score category-data)))
            (weighted-score (/ (* adjusted-score (get base-weight category-data)) u100))
        )
            (update-contributor-record contributor category weighted-score current-record)
            (update-daily-contribution contributor category adjusted-score current-day-block daily-data)
            (ok weighted-score)
        )
    )
)

;; Update contributor's overall record
(define-private (update-contributor-record
    (contributor principal)
    (category (string-ascii 20))
    (weighted-score uint)
    (current-record {total-contribution-score: uint, last-contribution-block: uint, active-streak-days: uint, lifetime-contributions: uint, category-scores: (list 10 {category: (string-ascii 20), score: uint, last-updated: uint})}))
    (let (
        (streak-bonus (calculate-streak-bonus contributor))
        (new-total-score (+ (get total-contribution-score current-record) weighted-score))
        (new-lifetime-count (+ (get lifetime-contributions current-record) u1))
        (updated-category-scores (update-category-score 
            (get category-scores current-record) category weighted-score))
    )
        (map-set contributor-records contributor {
            total-contribution-score: new-total-score,
            last-contribution-block: stacks-block-height,
            active-streak-days: streak-bonus,
            lifetime-contributions: new-lifetime-count,
            category-scores: updated-category-scores
        })
    )
)

;; Update daily contribution tracking
(define-private (update-daily-contribution
    (contributor principal)
    (category (string-ascii 20))
    (score uint)
    (day-block uint)
    (daily-data {total-daily-score: uint, contributions: (list 20 {category: (string-ascii 20), score: uint, timestamp: uint}), multiplier-applied: uint}))
    (let (
        (new-contribution {category: category, score: score, timestamp: stacks-block-height})
        (updated-contributions (unwrap-panic (as-max-len? 
            (append (get contributions daily-data) new-contribution) u20)))
        (new-daily-total (+ (get total-daily-score daily-data) score))
    )
        (map-set daily-contributions {contributor: contributor, day-block: day-block} {
            total-daily-score: new-daily-total,
            contributions: updated-contributions,
            multiplier-applied: (get multiplier-applied daily-data)
        })
    )
)

;; Calculate contribution streak bonus
(define-private (calculate-streak-bonus (contributor principal))
    (match (map-get? contributor-records contributor)
        record
            (let (
                (last-contribution (get last-contribution-block record))
                (current-day (get-day-block stacks-block-height))
                (last-day (get-day-block last-contribution))
                (current-streak (get active-streak-days record))
            )
                (if (is-eq (- current-day last-day) u1)
                    (+ current-streak u1)
                    (if (is-eq current-day last-day)
                        current-streak
                        u1)))
        u1
    )
)

;; Update category scores in contributor record
(define-private (update-category-score
    (category-scores (list 10 {category: (string-ascii 20), score: uint, last-updated: uint}))
    (category (string-ascii 20))
    (new-score uint))
    (let (
        (updated-entry {category: category, score: new-score, last-updated: stacks-block-height})
    )
        (unwrap-panic (as-max-len? (append category-scores updated-entry) u10))
    )
)

;; Helper functions
(define-private (min (a uint) (b uint))
    (if (< a b) a b)
)

(define-private (max (a uint) (b uint))
    (if (> a b) a b)
)

;; Get day block (simplified day calculation)
(define-private (get-day-block (block-num uint))
    (/ block-num (var-get contribution-window-blocks))
)

;; Calculate and distribute rewards for a period
(define-public (calculate-period-rewards (contributors (list 50 principal)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (let (
            (current-period (get-day-block stacks-block-height))
            (total-pool-for-period (/ (var-get available-reward-pool) u10))
        )
            (asserts! (<= total-pool-for-period (var-get available-reward-pool)) ERR-INSUFFICIENT-REWARD-POOL)
            (var-set available-reward-pool (- (var-get available-reward-pool) total-pool-for-period))
            (var-set last-distribution-block stacks-block-height)
            (ok (map calculate-individual-reward contributors))
        )
    )
)

;; Calculate individual reward for contributor
(define-private (calculate-individual-reward (contributor principal))
    (match (map-get? contributor-records contributor)
        record
            (let (
                (contribution-score (get total-contribution-score record))
                (streak-bonus (get active-streak-days record))
                (base-reward (/ (* contribution-score u100) u1000))
                (streak-multiplier (+ u100 (min (* streak-bonus u5) u50)))
                (final-reward (/ (* base-reward streak-multiplier) u100))
                (current-period (get-day-block stacks-block-height))
            )
                (map-set reward-distributions 
                    {contributor: contributor, distribution-period: current-period}
                    {
                        reward-amount: final-reward,
                        contribution-rank: u0,
                        bonus-percentage: (- streak-multiplier u100),
                        claimed: false,
                        distribution-block: stacks-block-height
                    })
                final-reward
            )
        u0
    )
)

;; Claim reward for a specific period
(define-public (claim-period-reward (period uint))
    (let (
        (reward-data (unwrap! (map-get? reward-distributions 
            {contributor: tx-sender, distribution-period: period}) ERR-CONTRIBUTION-NOT-FOUND))
    )
        (asserts! (not (get claimed reward-data)) ERR-REWARD-ALREADY-CLAIMED)
        (asserts! (> (get reward-amount reward-data) u0) ERR-INSUFFICIENT-REWARD-POOL)
        (map-set reward-distributions 
            {contributor: tx-sender, distribution-period: period}
            (merge reward-data {claimed: true}))
        (ok (get reward-amount reward-data))
    )
)

;; Apply decay to contribution scores
(define-public (apply-contribution-decay (contributors (list 30 principal)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (map process-contribution-decay contributors))
    )
)

;; Process decay for individual contributor
(define-private (process-contribution-decay (contributor principal))
    (match (map-get? contributor-records contributor)
        record
            (let (
                (blocks-since-contribution (- stacks-block-height (get last-contribution-block record)))
                (decay-periods (/ blocks-since-contribution (var-get contribution-window-blocks)))
                (decay-amount (min (* decay-periods u10) (/ (get total-contribution-score record) u4)))
                (new-score (max u0 (- (get total-contribution-score record) decay-amount)))
            )
                (if (> decay-periods u0)
                    (begin
                        (map-set contributor-records contributor
                            (merge record {
                                total-contribution-score: new-score,
                                active-streak-days: u0
                            }))
                        decay-amount)
                    u0)
            )
        u0
    )
)

;; Create team contribution pool
(define-public (create-team-pool
    (team-name (string-ascii 25))
    (members (list 20 principal))
    (pool-allocation uint)
    (distribution-method (string-ascii 15)))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (<= pool-allocation (var-get available-reward-pool)) ERR-INSUFFICIENT-REWARD-POOL)
        (var-set available-reward-pool (- (var-get available-reward-pool) pool-allocation))
        (ok (map-set team-contribution-pools team-name {
            team-members: members,
            pool-allocation: pool-allocation,
            distribution-method: distribution-method,
            last-distribution: stacks-block-height
        }))
    )
)

;; Distribute team pool rewards
(define-public (distribute-team-rewards (team-name (string-ascii 25)))
    (match (map-get? team-contribution-pools team-name)
        pool-data
            (let (
                (members (get team-members pool-data))
                (total-allocation (get pool-allocation pool-data))
                (reward-per-member (/ total-allocation (len members)))
            )
                (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
                (ok (fold distribute-team-member-reward members u0))
            )
        ERR-CONTRIBUTION-NOT-FOUND
    )
)

;; Helper function for team reward distribution
(define-private (distribute-team-member-reward (member principal) (counter uint))
    (let (
        (current-period (get-day-block stacks-block-height))
        (reward-amount u100)
    )
        (map-set reward-distributions 
            {contributor: member, distribution-period: current-period}
            {
                reward-amount: reward-amount,
                contribution-rank: u0,
                bonus-percentage: u0,
                claimed: false,
                distribution-block: stacks-block-height
            })
        (+ counter u1)
    )
)

;; Record reward for team member
(define-private (record-team-member-reward (member principal) (reward-amount uint))
    (let (
        (current-period (get-day-block stacks-block-height))
    )
        (map-set reward-distributions 
            {contributor: member, distribution-period: current-period}
            {
                reward-amount: reward-amount,
                contribution-rank: u0,
                bonus-percentage: u0,
                claimed: false,
                distribution-block: stacks-block-height
            })
        reward-amount
    )
)

;; Boost contributor's score with multiplier
(define-public (apply-contribution-boost
    (contributor principal)
    (multiplier-percentage uint)
    (duration-blocks uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= multiplier-percentage u100) (<= multiplier-percentage u300)) ERR-INVALID-MULTIPLIER)
        (match (map-get? contributor-records contributor)
            record
                (let (
                    (current-score (get total-contribution-score record))
                    (boost-amount (/ (* current-score (- multiplier-percentage u100)) u100))
                    (new-total-score (+ current-score boost-amount))
                )
                    (ok (map-set contributor-records contributor
                        (merge record {total-contribution-score: new-total-score})))
                )
            ERR-CONTRIBUTION-NOT-FOUND
        )
    )
)

;; Read-only functions

;; Get contributor statistics
(define-read-only (get-contributor-stats (contributor principal))
    (match (map-get? contributor-records contributor)
        record
            (let (
                (current-period (get-day-block stacks-block-height))
                (reward-data (map-get? reward-distributions {contributor: contributor, distribution-period: current-period}))
                (pending-reward (if (is-some reward-data)
                    (get reward-amount (unwrap-panic reward-data))
                    u0))
            )
                (ok {
                    total-score: (get total-contribution-score record),
                    active-streak: (get active-streak-days record),
                    lifetime-contributions: (get lifetime-contributions record),
                    last-contribution: (get last-contribution-block record),
                    pending-reward: pending-reward,
                    category-breakdown: (get category-scores record)
                })
            )
        ERR-CONTRIBUTION-NOT-FOUND
    )
)

;; Get reward pool status
(define-read-only (get-reward-pool-status)
    (ok {
        total-pool: (var-get total-reward-pool),
        available-pool: (var-get available-reward-pool),
        last-distribution: (var-get last-distribution-block),
        distribution-interval: (var-get reward-distribution-interval)
    })
)

;; Get contribution category information
(define-read-only (get-category-info (category (string-ascii 20)))
    (map-get? contribution-categories category)
)

;; Administrative functions

;; Replenish reward pool
(define-public (replenish-reward-pool (amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (var-set total-reward-pool (+ (var-get total-reward-pool) amount))
        (var-set available-reward-pool (+ (var-get available-reward-pool) amount))
        (ok true)
    )
)

;; Update system parameters
(define-public (update-system-parameters
    (window-blocks uint)
    (min-score uint)
    (distribution-interval uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (and (>= window-blocks u144) (<= window-blocks u4032)) ERR-INVALID-CONTRIBUTION)
        (asserts! (and (>= min-score u1) (<= min-score u100)) ERR-INVALID-CONTRIBUTION)
        (var-set contribution-window-blocks window-blocks)
        (var-set min-contribution-score min-score)
        (var-set reward-distribution-interval distribution-interval)
        (ok true)
    )
)

;; Get system configuration
(define-read-only (get-system-config)
    (ok {
        contribution-window: (var-get contribution-window-blocks),
        min-contribution: (var-get min-contribution-score),
        distribution-interval: (var-get reward-distribution-interval),
        contract-owner: (var-get contract-owner)
    })
)



;; Title: Token Vesting Contract
;; Description: A contract that manages token vesting schedules for employees/partners

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-INITIALIZED (err u101))
(define-constant ERR-NOT-FOUND (err u102))
(define-constant ERR-INVALID-SCHEDULE (err u103))
(define-constant ERR-NO-TOKENS-TO-CLAIM (err u104))

;; Data variables
(define-data-var contract-owner principal tx-sender)
(define-data-var total-tokens-locked uint u0)

;; Data maps
(define-map vesting-schedules
  principal
  {
    total-amount: uint,           ;; Total tokens to be vested
    start-block: uint,            ;; Block height when vesting starts
    cliff-length: uint,           ;; Number of blocks before first release
    vesting-length: uint,         ;; Total vesting duration in blocks
    vesting-interval: uint,       ;; Interval between releases (e.g., monthly)
    tokens-claimed: uint,         ;; Amount of tokens already claimed
    is-revocable: bool,          ;; Whether the schedule can be revoked
    is-active: bool              ;; Whether the schedule is still active
  }
)

;; Public functions

;; Initialize a new vesting schedule
(define-public (create-vesting-schedule
    (beneficiary principal)
    (total-amount uint)
    (start-block uint)
    (cliff-length uint)
    (vesting-length uint)
    (vesting-interval uint)
    (is-revocable bool))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (asserts! (> total-amount u0) ERR-INVALID-SCHEDULE)
    (asserts! (>= vesting-length cliff-length) ERR-INVALID-SCHEDULE)
    (asserts! (> vesting-interval u0) ERR-INVALID-SCHEDULE)
    
    ;; Check if schedule already exists and is active
    (match (get-vesting-schedule beneficiary)
      schedule (asserts! (not (get is-active schedule)) ERR-ALREADY-INITIALIZED)
      true
    )
    
    (map-set vesting-schedules
      beneficiary
      {
        total-amount: total-amount,
        start-block: start-block,
        cliff-length: cliff-length,
        vesting-length: vesting-length,
        vesting-interval: vesting-interval,
        tokens-claimed: u0,
        is-revocable: is-revocable,
        is-active: true
      }
    )
    
    (var-set total-tokens-locked (+ (var-get total-tokens-locked) total-amount))
    (ok true)
  )
)

;; Calculate claimable tokens for a beneficiary
(define-read-only (get-claimable-tokens (beneficiary principal))
  (match (get-vesting-schedule beneficiary)
    schedule 
      (let (
        (current-block block-height)
        (start-block (get start-block schedule))
        (cliff-end (+ start-block (get cliff-length schedule)))
        (vesting-end (+ start-block (get vesting-length schedule)))
      )
        (if (or (not (get is-active schedule)) (< current-block cliff-end))
          (ok u0)
          (let (
            (elapsed-blocks (- current-block start-block))
            (vested-amount (/ (* elapsed-blocks (get total-amount schedule)) (get vesting-length schedule)))
            (claimable (- vested-amount (get tokens-claimed schedule)))
          )
            (ok claimable)
          )
        )
      )
    (ok u0)
  )
)

;; Claim vested tokens
(define-public (claim-tokens)
  (let (
    (beneficiary tx-sender)
    (claimable (unwrap! (get-claimable-tokens beneficiary) ERR-NOT-FOUND))
  )
    (asserts! (> claimable u0) ERR-NO-TOKENS-TO-CLAIM)
    (match (get-vesting-schedule beneficiary)
      schedule 
        (begin
          (map-set vesting-schedules
            beneficiary
            (merge schedule { tokens-claimed: (+ (get tokens-claimed schedule) claimable) })
          )
          (var-set total-tokens-locked (- (var-get total-tokens-locked) claimable))
          ;; Here you would add the token transfer logic using ft-transfer?
          (ok claimable)
        )
      ERR-NOT-FOUND
    )
  )
)

;; Revoke vesting schedule (only for revocable schedules)
(define-public (revoke-schedule (beneficiary principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (match (get-vesting-schedule beneficiary)
      schedule 
        (begin
          (asserts! (get is-revocable schedule) ERR-NOT-AUTHORIZED)
          (asserts! (get is-active schedule) ERR-NOT-FOUND)
          (let (
            (unclaimed-tokens (- (get total-amount schedule) (get tokens-claimed schedule)))
          )
            (map-set vesting-schedules
              beneficiary
              (merge schedule { is-active: false })
            )
            (var-set total-tokens-locked (- (var-get total-tokens-locked) unclaimed-tokens))
            (ok unclaimed-tokens)
          )
        )
      ERR-NOT-FOUND
    )
  )
)

;; Getter for vesting schedule
(define-read-only (get-vesting-schedule (beneficiary principal))
  (map-get? vesting-schedules beneficiary)
)

;; Get total locked tokens
(define-read-only (get-total-locked-tokens)
  (ok (var-get total-tokens-locked))
)


(define-public (modify-vesting-schedule 
    (beneficiary principal)
    (new-vesting-length uint)
    (new-cliff-length uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (match (get-vesting-schedule beneficiary)
            schedule
                (begin
                    (asserts! (get is-active schedule) ERR-NOT-FOUND)
                    (asserts! (>= new-vesting-length new-cliff-length) ERR-INVALID-SCHEDULE)
                    (map-set vesting-schedules
                        beneficiary
                        (merge schedule {
                            vesting-length: new-vesting-length,
                            cliff-length: new-cliff-length
                        }))
                    (ok true))
            ERR-NOT-FOUND)))


(define-read-only (get-vesting-status (beneficiary principal))
    (match (get-vesting-schedule beneficiary)
        schedule
            (let (
                (current-block block-height)
                (start-block (get start-block schedule))
                (cliff-end (+ start-block (get cliff-length schedule)))
                (vesting-end (+ start-block (get vesting-length schedule)))
            )
                (ok {
                    is-active: (get is-active schedule),
                    in-cliff-period: (< current-block cliff-end),
                    fully-vested: (>= current-block vesting-end),
                    total-claimed: (get tokens-claimed schedule),
                    remaining-amount: (- (get total-amount schedule) (get tokens-claimed schedule))
                }))
        ERR-NOT-FOUND))

(define-data-var contract-paused bool false)

(define-public (toggle-contract-pause)
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (ok (var-set contract-paused (not (var-get contract-paused))))))

;; Add to the beginning of create-vesting-schedule and claim-tokens:
(asserts! (not (var-get contract-paused)) ERR-NOT-AUTHORIZED)



;; Add this constant
(define-constant ERR-NO-BALANCE (err u105))

;; Add this function
(define-public (emergency-withdraw (amount uint))
    (begin
        (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
        (asserts! (>= (var-get total-tokens-locked) amount) ERR-NO-BALANCE)
        (var-set total-tokens-locked (- (var-get total-tokens-locked) amount))
        ;; Add token transfer logic here
        (ok amount)))



(define-private (create-single-schedule 
    (beneficiary principal) 
    (amount uint) 
    (previous-response bool)
    (start-block uint)
    (cliff-length uint)
    (vesting-length uint)
    (vesting-interval uint)
    (is-revocable bool))
    (unwrap! (create-vesting-schedule beneficiary amount start-block cliff-length vesting-length vesting-interval is-revocable) false))

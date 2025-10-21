(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-ESCROW-NOT-FOUND (err u101))
(define-constant ERR-INVALID-AMOUNT (err u102))
(define-constant ERR-ESCROW-ALREADY-EXISTS (err u103))
(define-constant ERR-WRONG-PHASE (err u104))
(define-constant ERR-NOT-PARTICIPANT (err u105))
(define-constant ERR-ALREADY-CONFIRMED (err u106))
(define-constant ERR-INSUFFICIENT-BALANCE (err u107))
(define-constant ERR-DISPUTE-PERIOD-NOT-PASSED (err u108))
(define-constant ERR-ALREADY-DISPUTED (err u109))
(define-constant ERR-MILESTONE-NOT-FOUND (err u110))
(define-constant ERR-MILESTONE-ALREADY-RELEASED (err u111))
(define-constant ERR-MILESTONE-INVALID-DATA (err u112))
(define-constant ERR-INVALID-FEE (err u1007))
(define-constant ERR-OWNER-ONLY (err u1008))

(define-constant PHASE-PENDING u0)
(define-constant PHASE-ACTIVE u1)
(define-constant PHASE-CONFIRMING u2)
(define-constant PHASE-COMPLETED u3)
(define-constant PHASE-DISPUTED u4)
(define-constant PHASE-CANCELLED u5)

(define-constant DISPUTE-PERIOD u144)
(define-constant MAX-FEE-PERCENTAGE u500)
(define-constant ERR-FEE-EXCEEDED (err u113))

(define-data-var next-escrow-id uint u1)

(define-map arbiter-fees principal uint)
(define-map arbiter-earnings principal uint)

(define-map escrows uint {
    buyer: principal,
    seller: principal,
    amount: uint,
    phase: uint,
    created-at: uint,
    service-description: (string-ascii 256),
    buyer-confirmed: bool,
    seller-confirmed: bool,
    dispute-raised-at: (optional uint),
    arbiter: (optional principal)
})

(define-map user-escrows principal (list 50 uint))
(define-map escrow-balances uint uint)
(define-map milestones {escrow-id: uint, index: uint} {
    amount: uint,
    description: (string-ascii 128),
    released: bool,
    disputed: bool,
    buyer-confirmed: bool,
    seller-confirmed: bool,
    arbiter: (optional principal)
})
(define-map milestone-counts uint uint)
(define-map arbiter-payments {escrow-id: uint} {arbiter: principal, amount: uint, paid: bool})

(define-data-var fee-percentage uint u100)
(define-data-var fee-enabled bool true)
(define-data-var platform-recipient principal tx-sender)

(define-private (calculate-fee (escrow-amount uint))
  (let (
    (fee-rate (var-get fee-percentage))
  )
  (/ (* escrow-amount fee-rate) u10000)
  )
)

(define-private (collect-platform-fee (escrow-id uint) (total-amount uint))
  (let (
    (fee-active (var-get fee-enabled))
    (fee-amount (calculate-fee total-amount))
    (recipient (var-get platform-recipient))
  )
  (if (and fee-active (> fee-amount u0))
    (begin
      (try! (as-contract (stx-transfer? fee-amount tx-sender recipient)))
      (ok fee-amount)
    )
    (ok u0)
  )
  )
)

(define-private (collect-arbiter-fee (escrow-id uint) (total-amount uint) (arbiter principal))
  (let (
    (fee-active (var-get fee-enabled))
    (total-fee (calculate-fee total-amount))
    (arbiter-portion (/ total-fee u2))
    (platform-portion (- total-fee arbiter-portion))
    (recipient (var-get platform-recipient))
  )
  (if (and fee-active (> total-fee u0))
    (begin
      (try! (as-contract (stx-transfer? arbiter-portion tx-sender arbiter)))
      (try! (as-contract (stx-transfer? platform-portion tx-sender recipient)))
      (map-set arbiter-payments
        {escrow-id: escrow-id}
        {arbiter: arbiter, amount: arbiter-portion, paid: true}
      )
      (ok total-fee)
    )
    (ok u0)
  )
  )
)

(define-public (create-escrow (seller principal) (amount uint) (service-description (string-ascii 256)))
    (let (
        (escrow-id (var-get next-escrow-id))
        (current-balance (stx-get-balance tx-sender))
    )
    (asserts! (> amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= current-balance amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (not (is-eq tx-sender seller)) ERR-UNAUTHORIZED)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set escrows escrow-id {
        buyer: tx-sender,
        seller: seller,
        amount: amount,
        phase: PHASE-ACTIVE,
        created-at: stacks-block-height,
        service-description: service-description,
        buyer-confirmed: false,
        seller-confirmed: false,
        dispute-raised-at: none,
        arbiter: none
    })
    
    (map-set escrow-balances escrow-id amount)
    
    (let (
        (buyer-escrows (default-to (list) (map-get? user-escrows tx-sender)))
        (seller-escrows (default-to (list) (map-get? user-escrows seller)))
    )
        (map-set user-escrows tx-sender (unwrap! (as-max-len? (append buyer-escrows escrow-id) u50) ERR-UNAUTHORIZED))
        (map-set user-escrows seller (unwrap! (as-max-len? (append seller-escrows escrow-id) u50) ERR-UNAUTHORIZED))
    )
    
    (var-set next-escrow-id (+ escrow-id u1))
    (ok escrow-id)
    )
)

(define-public (create-milestone-escrow (seller principal) (milestone-amounts (list 20 uint)) (milestone-descriptions (list 20 (string-ascii 128))))
    (let (
        (escrow-id (var-get next-escrow-id))
        (total-amount (fold + milestone-amounts u0))
        (milestone-count (len milestone-amounts))
        (current-balance (stx-get-balance tx-sender))
    )
    (asserts! (> milestone-count u0) ERR-MILESTONE-INVALID-DATA)
    (asserts! (is-eq milestone-count (len milestone-descriptions)) ERR-MILESTONE-INVALID-DATA)
    (asserts! (> total-amount u0) ERR-INVALID-AMOUNT)
    (asserts! (>= current-balance total-amount) ERR-INSUFFICIENT-BALANCE)
    (asserts! (not (is-eq tx-sender seller)) ERR-UNAUTHORIZED)
    (asserts! (fold and (map > milestone-amounts (list u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0 u0)) true) ERR-INVALID-AMOUNT)
    
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    
    (map-set escrows escrow-id {
        buyer: tx-sender,
        seller: seller,
        amount: total-amount,
        phase: PHASE-ACTIVE,
        created-at: stacks-block-height,
        service-description: "Milestone-based escrow",
        buyer-confirmed: false,
        seller-confirmed: false,
        dispute-raised-at: none,
        arbiter: none
    })
    
    (map-set escrow-balances escrow-id total-amount)
    (map-set milestone-counts escrow-id milestone-count)
    
    (fold store-milestone-fold 
        (map create-milestone-tuple 
             milestone-amounts 
             milestone-descriptions 
             (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9 u10 u11 u12 u13 u14 u15 u16 u17 u18 u19))
        {escrow-id: escrow-id, success: true})
    
    (let (
        (buyer-escrows (default-to (list) (map-get? user-escrows tx-sender)))
        (seller-escrows (default-to (list) (map-get? user-escrows seller)))
    )
        (map-set user-escrows tx-sender (unwrap! (as-max-len? (append buyer-escrows escrow-id) u50) ERR-UNAUTHORIZED))
        (map-set user-escrows seller (unwrap! (as-max-len? (append seller-escrows escrow-id) u50) ERR-UNAUTHORIZED))
    )
    
    (var-set next-escrow-id (+ escrow-id u1))
    (ok escrow-id)
    )
)

(define-public (confirm-service (escrow-id uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (caller tx-sender)
    )
    (asserts! (is-eq (get phase escrow-data) PHASE-ACTIVE) ERR-WRONG-PHASE)
    (asserts! (or (is-eq caller (get buyer escrow-data)) 
                  (is-eq caller (get seller escrow-data))) ERR-NOT-PARTICIPANT)
    
    (if (is-eq caller (get buyer escrow-data))
        (begin
            (asserts! (not (get buyer-confirmed escrow-data)) ERR-ALREADY-CONFIRMED)
            (map-set escrows escrow-id 
                (merge escrow-data { buyer-confirmed: true, phase: PHASE-CONFIRMING }))
        )
        (begin
            (asserts! (not (get seller-confirmed escrow-data)) ERR-ALREADY-CONFIRMED)
            (map-set escrows escrow-id 
                (merge escrow-data { seller-confirmed: true, phase: PHASE-CONFIRMING }))
        )
    )
    
    (let ((updated-escrow (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND)))
        (if (and (get buyer-confirmed updated-escrow) (get seller-confirmed updated-escrow))
            (complete-escrow escrow-id)
            (ok true)
        )
    )
    )
)

(define-public (confirm-milestone (escrow-id uint) (milestone-index uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (milestone-key {escrow-id: escrow-id, index: milestone-index})
        (milestone-data (unwrap! (map-get? milestones milestone-key) ERR-MILESTONE-NOT-FOUND))
        (caller tx-sender)
    )
    (asserts! (is-eq (get phase escrow-data) PHASE-ACTIVE) ERR-WRONG-PHASE)
    (asserts! (or (is-eq caller (get buyer escrow-data)) 
                  (is-eq caller (get seller escrow-data))) ERR-NOT-PARTICIPANT)
    (asserts! (not (get released milestone-data)) ERR-MILESTONE-ALREADY-RELEASED)
    (asserts! (not (get disputed milestone-data)) ERR-WRONG-PHASE)
    
    (if (is-eq caller (get buyer escrow-data))
        (begin
            (asserts! (not (get buyer-confirmed milestone-data)) ERR-ALREADY-CONFIRMED)
            (map-set milestones milestone-key 
                (merge milestone-data { buyer-confirmed: true }))
        )
        (begin
            (asserts! (not (get seller-confirmed milestone-data)) ERR-ALREADY-CONFIRMED)
            (map-set milestones milestone-key 
                (merge milestone-data { seller-confirmed: true }))
        )
    )
    
    (let ((updated-milestone (unwrap! (map-get? milestones milestone-key) ERR-MILESTONE-NOT-FOUND)))
        (if (and (get buyer-confirmed updated-milestone) (get seller-confirmed updated-milestone))
            (release-milestone-funds escrow-id milestone-index)
            (ok true)
        )
    )
    )
)

(define-public (raise-dispute (escrow-id uint) (arbiter principal))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (caller tx-sender)
    )
    (asserts! (or (is-eq (get phase escrow-data) PHASE-ACTIVE)
                  (is-eq (get phase escrow-data) PHASE-CONFIRMING)) ERR-WRONG-PHASE)
    (asserts! (or (is-eq caller (get buyer escrow-data)) 
                  (is-eq caller (get seller escrow-data))) ERR-NOT-PARTICIPANT)
    (asserts! (is-none (get dispute-raised-at escrow-data)) ERR-ALREADY-DISPUTED)
    
    (map-set escrows escrow-id 
        (merge escrow-data { 
            phase: PHASE-DISPUTED, 
            dispute-raised-at: (some stacks-block-height),
            arbiter: (some arbiter)
        }))
    (ok true)
    )
)

(define-public (resolve-dispute (escrow-id uint) (award-to-seller bool))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (caller tx-sender)
        (arbiter (unwrap! (get arbiter escrow-data) ERR-UNAUTHORIZED))
    )
    (asserts! (is-eq (get phase escrow-data) PHASE-DISPUTED) ERR-WRONG-PHASE)
    (asserts! (is-eq caller arbiter) ERR-UNAUTHORIZED)
    
    (if award-to-seller
        (release-funds-to-seller escrow-id)
        (refund-buyer escrow-id)
    )
    )
)

(define-public (set-fee-config (new-fee-percentage uint) (enabled bool) (recipient principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (<= new-fee-percentage u1000) ERR-INVALID-FEE)
    (var-set fee-percentage new-fee-percentage)
    (var-set fee-enabled enabled)
    (var-set platform-recipient recipient)
    (ok true)
  )
)

(define-read-only (get-fee-config)
  {
    percentage: (var-get fee-percentage),
    enabled: (var-get fee-enabled),
    recipient: (var-get platform-recipient)
  }
)

(define-read-only (get-fee-percentage)
  (var-get fee-percentage)
)

(define-read-only (is-fee-enabled)
  (var-get fee-enabled)
)

(define-read-only (get-platform-recipient)
  (var-get platform-recipient)
)

(define-public (set-arbiter-fee (arbiter-fee-pct uint))
    (begin
        (asserts! (<= arbiter-fee-pct MAX-FEE-PERCENTAGE) ERR-FEE-EXCEEDED)
        (map-set arbiter-fees tx-sender arbiter-fee-pct)
        (ok true)
    )
)

(define-public (cancel-escrow (escrow-id uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (caller tx-sender)
        (dispute-time (get dispute-raised-at escrow-data))
    )
    (asserts! (is-eq caller (get buyer escrow-data)) ERR-UNAUTHORIZED)
    (asserts! (is-eq (get phase escrow-data) PHASE-ACTIVE) ERR-WRONG-PHASE)
    
    (refund-buyer escrow-id)
    )
)

(define-public (raise-milestone-dispute (escrow-id uint) (milestone-index uint) (arbiter principal))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (milestone-key {escrow-id: escrow-id, index: milestone-index})
        (milestone-data (unwrap! (map-get? milestones milestone-key) ERR-MILESTONE-NOT-FOUND))
        (caller tx-sender)
    )
    (asserts! (is-eq (get phase escrow-data) PHASE-ACTIVE) ERR-WRONG-PHASE)
    (asserts! (or (is-eq caller (get buyer escrow-data)) 
                  (is-eq caller (get seller escrow-data))) ERR-NOT-PARTICIPANT)
    (asserts! (not (get released milestone-data)) ERR-MILESTONE-ALREADY-RELEASED)
    (asserts! (not (get disputed milestone-data)) ERR-ALREADY-DISPUTED)
    
    (map-set milestones milestone-key 
        (merge milestone-data { 
            disputed: true,
            arbiter: (some arbiter)
        }))
    (map-set escrows escrow-id (merge escrow-data { phase: PHASE-DISPUTED }))
    (ok true)
    )
)

(define-public (resolve-milestone-dispute (escrow-id uint) (milestone-index uint) (award-to-seller bool))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (milestone-key {escrow-id: escrow-id, index: milestone-index})
        (milestone-data (unwrap! (map-get? milestones milestone-key) ERR-MILESTONE-NOT-FOUND))
        (caller tx-sender)
        (arbiter (unwrap! (get arbiter milestone-data) ERR-UNAUTHORIZED))
    )
    (asserts! (is-eq (get phase escrow-data) PHASE-DISPUTED) ERR-WRONG-PHASE)
    (asserts! (is-eq caller arbiter) ERR-UNAUTHORIZED)
    (asserts! (get disputed milestone-data) ERR-WRONG-PHASE)
    
    (if award-to-seller
        (begin
            (map-set milestones milestone-key 
                (merge milestone-data { 
                    disputed: false,
                    buyer-confirmed: true,
                    seller-confirmed: true
                }))
            (release-milestone-funds escrow-id milestone-index)
        )
        (begin
            (map-set milestones milestone-key 
                (merge milestone-data { 
                    disputed: false,
                    released: true
                }))
            (ok true)
        )
    )
    )
)

(define-public (emergency-cancel (escrow-id uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (caller tx-sender)
        (dispute-time (get dispute-raised-at escrow-data))
    )
    (asserts! (or (is-eq caller (get buyer escrow-data)) 
                  (is-eq caller (get seller escrow-data))) ERR-NOT-PARTICIPANT)
    (asserts! (is-eq (get phase escrow-data) PHASE-DISPUTED) ERR-WRONG-PHASE)
    (asserts! (is-some dispute-time) ERR-UNAUTHORIZED)
    (asserts! (>= (- stacks-block-height (unwrap-panic dispute-time)) DISPUTE-PERIOD) ERR-DISPUTE-PERIOD-NOT-PASSED)
    
    (refund-buyer escrow-id)
    )
)

(define-private (release-milestone-funds (escrow-id uint) (milestone-index uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (milestone-key {escrow-id: escrow-id, index: milestone-index})
        (milestone-data (unwrap! (map-get? milestones milestone-key) ERR-MILESTONE-NOT-FOUND))
        (milestone-amount (get amount milestone-data))
        (current-balance (unwrap! (map-get? escrow-balances escrow-id) ERR-ESCROW-NOT-FOUND))
        (net-amount (unwrap! (collect-fees-on-milestone escrow-id milestone-amount) ERR-ESCROW-NOT-FOUND))
    )
    (try! (as-contract (stx-transfer? net-amount tx-sender (get seller escrow-data))))
    (map-set milestones milestone-key (merge milestone-data { released: true }))
    (map-set escrow-balances escrow-id (- current-balance milestone-amount))
    
    (if (is-eq (- current-balance milestone-amount) u0)
        (begin
            (map-set escrows escrow-id (merge escrow-data { phase: PHASE-COMPLETED }))
            (map-delete escrow-balances escrow-id)
        )
        true
    )
    (ok true)
    )
)

(define-private (create-milestone-tuple (amount uint) (description (string-ascii 128)) (index uint))
    {amount: amount, description: description, index: index}
)

(define-private (store-milestone-fold (milestone-tuple {amount: uint, description: (string-ascii 128), index: uint}) 
                                     (acc {escrow-id: uint, success: bool}))
    (let ((escrow-id (get escrow-id acc)))
        (if (> (get amount milestone-tuple) u0)
            (begin
                (map-set milestones 
                    {escrow-id: escrow-id, index: (get index milestone-tuple)} 
                    {
                        amount: (get amount milestone-tuple),
                        description: (get description milestone-tuple),
                        released: false,
                        disputed: false,
                        buyer-confirmed: false,
                        seller-confirmed: false,
                        arbiter: none
                    })
                acc
            )
            acc
        )
    )
)

(define-private (complete-escrow (escrow-id uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
    )
    (release-funds-to-seller escrow-id)
    )
)

(define-private (release-funds-to-seller (escrow-id uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (total-amount (unwrap! (map-get? escrow-balances escrow-id) ERR-ESCROW-NOT-FOUND))
        (net-amount (unwrap! (collect-fees-on-resolution escrow-id total-amount) ERR-ESCROW-NOT-FOUND))
    )
    (try! (as-contract (stx-transfer? net-amount tx-sender (get seller escrow-data))))
    (map-set escrows escrow-id (merge escrow-data { phase: PHASE-COMPLETED }))
    (map-delete escrow-balances escrow-id)
    (ok true)
    )
)

(define-private (refund-buyer (escrow-id uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (amount (unwrap! (map-get? escrow-balances escrow-id) ERR-ESCROW-NOT-FOUND))
    )
    (try! (as-contract (stx-transfer? amount tx-sender (get buyer escrow-data))))
    (map-set escrows escrow-id (merge escrow-data { phase: PHASE-CANCELLED }))
    (map-delete escrow-balances escrow-id)
    (ok true)
    )
)

(define-read-only (get-escrow (escrow-id uint))
    (map-get? escrows escrow-id)
)

(define-read-only (get-escrow-balance (escrow-id uint))
    (map-get? escrow-balances escrow-id)
)

(define-read-only (get-user-escrows (user principal))
    (default-to (list) (map-get? user-escrows user))
)

(define-read-only (get-next-escrow-id)
    (var-get next-escrow-id)
)

(define-read-only (is-escrow-participant (escrow-id uint) (user principal))
    (match (map-get? escrows escrow-id)
        escrow-data (or (is-eq user (get buyer escrow-data)) 
                       (is-eq user (get seller escrow-data)))
        false
    )
)

(define-read-only (get-escrow-phase-name (phase uint))
    (if (is-eq phase PHASE-PENDING) "pending"
    (if (is-eq phase PHASE-ACTIVE) "active"
    (if (is-eq phase PHASE-CONFIRMING) "confirming"
    (if (is-eq phase PHASE-COMPLETED) "completed"
    (if (is-eq phase PHASE-DISPUTED) "disputed"
    (if (is-eq phase PHASE-CANCELLED) "cancelled"
    "unknown"))))))
)

(define-read-only (can-dispute (escrow-id uint))
    (match (map-get? escrows escrow-id)
        escrow-data (and (or (is-eq (get phase escrow-data) PHASE-ACTIVE)
                            (is-eq (get phase escrow-data) PHASE-CONFIRMING))
                        (is-none (get dispute-raised-at escrow-data)))
        false
    )
)

(define-read-only (get-contract-balance)
    (stx-get-balance (as-contract tx-sender))
)

(define-read-only (get-milestone (escrow-id uint) (milestone-index uint))
    (map-get? milestones {escrow-id: escrow-id, index: milestone-index})
)

(define-read-only (get-milestone-count (escrow-id uint))
    (default-to u0 (map-get? milestone-counts escrow-id))
)

(define-read-only (get-releasable-amount (escrow-id uint))
    (default-to u0 (map-get? escrow-balances escrow-id))
)

(define-read-only (get-fee-amount (arbiter (optional principal)) (amount uint))
    (match arbiter
        arb-principal
        (let ((fee-pct (default-to u0 (map-get? arbiter-fees arb-principal))))
            (/ (* amount fee-pct) u10000)
        )
        u0
    )
)

(define-read-only (get-arbiter-fee (arbiter principal))
    (ok (default-to u0 (map-get? arbiter-fees arbiter)))
)

(define-read-only (get-arbiter-earnings (arbiter principal))
    (ok (default-to u0 (map-get? arbiter-earnings arbiter)))
)

(define-private (collect-fees-on-resolution (escrow-id uint) (amount uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (arbiter (get arbiter escrow-data))
        (fee-amount (get-fee-amount arbiter amount))
        (net-amount (- amount fee-amount))
    )
    (if (and (is-some arbiter) (> fee-amount u0))
        (begin
            (try! (as-contract (stx-transfer? fee-amount tx-sender (unwrap-panic arbiter))))
            (map-set arbiter-earnings (unwrap-panic arbiter)
                (+ (default-to u0 (map-get? arbiter-earnings (unwrap-panic arbiter))) fee-amount)
            )
            (ok net-amount)
        )
        (ok amount)
    )
    )
)

(define-private (collect-fees-on-milestone (escrow-id uint) (amount uint))
    (let (
        (escrow-data (unwrap! (map-get? escrows escrow-id) ERR-ESCROW-NOT-FOUND))
        (arbiter (get arbiter escrow-data))
        (fee-amount (get-fee-amount arbiter amount))
        (net-amount (- amount fee-amount))
    )
    (if (and (is-some arbiter) (> fee-amount u0))
        (begin
            (try! (as-contract (stx-transfer? fee-amount tx-sender (unwrap-panic arbiter))))
            (map-set arbiter-earnings (unwrap-panic arbiter)
                (+ (default-to u0 (map-get? arbiter-earnings (unwrap-panic arbiter))) fee-amount)
            )
            (ok net-amount)
        )
        (ok amount)
    )
    )
)

(define-read-only (get-arbiter-payment (escrow-id uint))
  (map-get? arbiter-payments {escrow-id: escrow-id})
)

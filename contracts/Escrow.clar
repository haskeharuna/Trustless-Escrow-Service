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

(define-constant PHASE-PENDING u0)
(define-constant PHASE-ACTIVE u1)
(define-constant PHASE-CONFIRMING u2)
(define-constant PHASE-COMPLETED u3)
(define-constant PHASE-DISPUTED u4)
(define-constant PHASE-CANCELLED u5)

(define-constant DISPUTE-PERIOD u144)

(define-data-var next-escrow-id uint u1)

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
        (amount (unwrap! (map-get? escrow-balances escrow-id) ERR-ESCROW-NOT-FOUND))
    )
    (try! (as-contract (stx-transfer? amount tx-sender (get seller escrow-data))))
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

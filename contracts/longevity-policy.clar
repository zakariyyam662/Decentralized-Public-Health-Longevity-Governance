;; Longevity Policy Contract
;; Manages policies for extended lifespans and governance decisions

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-not-found (err u201))
(define-constant err-already-voted (err u202))
(define-constant err-unauthorized (err u203))
(define-constant err-voting-closed (err u204))

;; Data Variables
(define-data-var next-policy-id uint u1)
(define-data-var voting-period uint u1440) ;; blocks (~10 days)

;; Data Maps
(define-map policies
  { policy-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    proposer: principal,
    creation-date: uint,
    voting-end: uint,
    votes-for: uint,
    votes-against: uint,
    status: (string-ascii 20), ;; "active", "passed", "rejected", "implemented"
    implementation-date: (optional uint)
  }
)

(define-map policy-votes
  { policy-id: uint, voter: principal }
  { vote: bool, voting-power: uint }
)

;; Public Functions

;; Propose a new policy
(define-public (propose-policy (title (string-ascii 100)) (description (string-ascii 500)))
  (let
    (
      (policy-id (var-get next-policy-id))
      (voting-end (+ block-height (var-get voting-period)))
    )
    ;; Check if proposer is verified authority
    (asserts! (is-verified-proposer tx-sender) err-unauthorized)

    (map-set policies
      { policy-id: policy-id }
      {
        title: title,
        description: description,
        proposer: tx-sender,
        creation-date: block-height,
        voting-end: voting-end,
        votes-for: u0,
        votes-against: u0,
        status: "active",
        implementation-date: none
      }
    )

    (var-set next-policy-id (+ policy-id u1))
    (ok policy-id)
  )
)

;; Vote on a policy
(define-public (vote-on-policy (policy-id uint) (vote bool))
  (let
    (
      (voter tx-sender)
      (voting-power (get-voting-power voter))
    )
    (match (map-get? policies { policy-id: policy-id })
      policy-data
      (begin
        (asserts! (< block-height (get voting-end policy-data)) err-voting-closed)
        (asserts! (is-none (map-get? policy-votes { policy-id: policy-id, voter: voter })) err-already-voted)

        ;; Record vote
        (map-set policy-votes
          { policy-id: policy-id, voter: voter }
          { vote: vote, voting-power: voting-power }
        )

        ;; Update vote counts
        (if vote
          (map-set policies
            { policy-id: policy-id }
            (merge policy-data { votes-for: (+ (get votes-for policy-data) voting-power) })
          )
          (map-set policies
            { policy-id: policy-id }
            (merge policy-data { votes-against: (+ (get votes-against policy-data) voting-power) })
          )
        )

        (ok true)
      )
      err-not-found
    )
  )
)

;; Finalize policy voting
(define-public (finalize-policy (policy-id uint))
  (match (map-get? policies { policy-id: policy-id })
    policy-data
    (begin
      (asserts! (>= block-height (get voting-end policy-data)) err-voting-closed)
      (asserts! (is-eq (get status policy-data) "active") err-unauthorized)

      (let
        (
          (votes-for (get votes-for policy-data))
          (votes-against (get votes-against policy-data))
          (new-status (if (> votes-for votes-against) "passed" "rejected"))
        )
        (map-set policies
          { policy-id: policy-id }
          (merge policy-data { status: new-status })
        )
        (ok new-status)
      )
    )
    err-not-found
  )
)

;; Implement a passed policy
(define-public (implement-policy (policy-id uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (match (map-get? policies { policy-id: policy-id })
      policy-data
      (begin
        (asserts! (is-eq (get status policy-data) "passed") err-unauthorized)
        (map-set policies
          { policy-id: policy-id }
          (merge policy-data {
            status: "implemented",
            implementation-date: (some block-height)
          })
        )
        (ok true)
      )
      err-not-found
    )
  )
)

;; Read-only Functions

;; Get policy details
(define-read-only (get-policy (policy-id uint))
  (map-get? policies { policy-id: policy-id })
)

;; Get vote details
(define-read-only (get-vote (policy-id uint) (voter principal))
  (map-get? policy-votes { policy-id: policy-id, voter: voter })
)

;; Check if user is verified proposer
(define-read-only (is-verified-proposer (proposer principal))
  (match (contract-call? .health-authority get-authority-by-principal proposer)
    authority-data
    (get verified authority-data)
    false
  )
)

;; Get voting power (simplified - based on reputation)
(define-read-only (get-voting-power (voter principal))
  (match (contract-call? .health-authority get-authority-by-principal voter)
    authority-data
    (+ u1 (/ (get reputation-score authority-data) u10))
    u1
  )
)

;; Get total policies count
(define-read-only (get-total-policies)
  (- (var-get next-policy-id) u1)
)

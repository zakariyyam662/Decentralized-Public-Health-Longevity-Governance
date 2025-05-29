;; Ethical Framework Contract
;; Ensures responsible longevity governance and ethical compliance

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u400))
(define-constant err-not-found (err u401))
(define-constant err-unauthorized (err u402))
(define-constant err-already-reviewed (err u403))
(define-constant err-invalid-score (err u404))

;; Data Variables
(define-data-var next-review-id uint u1)
(define-data-var ethics-committee-size uint u5)

;; Data Maps
(define-map ethical-guidelines
  { guideline-id: uint }
  {
    title: (string-ascii 100),
    description: (string-ascii 500),
    category: (string-ascii 50),
    severity-level: uint, ;; 1-5 scale
    active: bool
  }
)

(define-map ethical-reviews
  { review-id: uint }
  {
    subject-type: (string-ascii 50), ;; "policy", "allocation", "research"
    subject-id: uint,
    reviewer: principal,
    compliance-score: uint, ;; 0-100 scale
    violations: (list 10 uint), ;; guideline IDs
    review-date: uint,
    status: (string-ascii 20), ;; "pending", "approved", "rejected", "conditional"
    comments: (string-ascii 300)
  }
)

(define-map ethics-committee
  { member: principal }
  { appointed-date: uint, active: bool }
)

(define-map compliance-scores
  { entity: principal }
  { total-score: uint, review-count: uint, last-updated: uint }
)

;; Public Functions

;; Add ethical guideline (owner only)
(define-public (add-guideline (guideline-id uint) (title (string-ascii 100)) (description (string-ascii 500)) (category (string-ascii 50)) (severity-level uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (and (>= severity-level u1) (<= severity-level u5)) err-invalid-score)

    (map-set ethical-guidelines
      { guideline-id: guideline-id }
      {
        title: title,
        description: description,
        category: category,
        severity-level: severity-level,
        active: true
      }
    )
    (ok true)
  )
)

;; Appoint ethics committee member
(define-public (appoint-committee-member (member principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set ethics-committee
      { member: member }
      { appointed-date: block-height, active: true }
    )
    (ok true)
  )
)

;; Submit ethical review
(define-public (submit-review (subject-type (string-ascii 50)) (subject-id uint) (compliance-score uint) (violations (list 10 uint)) (comments (string-ascii 300)))
  (let
    (
      (review-id (var-get next-review-id))
      (reviewer tx-sender)
    )
    (asserts! (is-committee-member reviewer) err-unauthorized)
    (asserts! (<= compliance-score u100) err-invalid-score)

    (map-set ethical-reviews
      { review-id: review-id }
      {
        subject-type: subject-type,
        subject-id: subject-id,
        reviewer: reviewer,
        compliance-score: compliance-score,
        violations: violations,
        review-date: block-height,
        status: (if (>= compliance-score u70) "approved" "conditional"),
        comments: comments
      }
    )

    (var-set next-review-id (+ review-id u1))
    (ok review-id)
  )
)

;; Update compliance score for entity
(define-public (update-compliance-score (entity principal) (new-score uint))
  (begin
    (asserts! (is-committee-member tx-sender) err-unauthorized)
    (asserts! (<= new-score u100) err-invalid-score)

    (match (map-get? compliance-scores { entity: entity })
      current-scores
      (let
        (
          (review-count (get review-count current-scores))
          (total-score (get total-score current-scores))
          (new-total (+ total-score new-score))
          (new-count (+ review-count u1))
        )
        (map-set compliance-scores
          { entity: entity }
          {
            total-score: new-total,
            review-count: new-count,
            last-updated: block-height
          }
        )
      )
      (map-set compliance-scores
        { entity: entity }
        {
          total-score: new-score,
          review-count: u1,
          last-updated: block-height
        }
      )
    )
    (ok true)
  )
)

;; Flag ethical violation
(define-public (flag-violation (subject-type (string-ascii 50)) (subject-id uint) (guideline-id uint) (severity uint))
  (let
    (
      (review-id (var-get next-review-id))
    )
    (asserts! (is-committee-member tx-sender) err-unauthorized)
    (asserts! (and (>= severity u1) (<= severity u5)) err-invalid-score)

    (map-set ethical-reviews
      { review-id: review-id }
      {
        subject-type: subject-type,
        subject-id: subject-id,
        reviewer: tx-sender,
        compliance-score: (- u100 (* severity u20)),
        violations: (list guideline-id),
        review-date: block-height,
        status: "rejected",
        comments: "Ethical violation flagged"
      }
    )

    (var-set next-review-id (+ review-id u1))
    (ok review-id)
  )
)

;; Read-only Functions

;; Get ethical guideline
(define-read-only (get-guideline (guideline-id uint))
  (map-get? ethical-guidelines { guideline-id: guideline-id })
)

;; Get ethical review
(define-read-only (get-review (review-id uint))
  (map-get? ethical-reviews { review-id: review-id })
)

;; Check if user is committee member
(define-read-only (is-committee-member (member principal))
  (match (map-get? ethics-committee { member: member })
    committee-data
    (get active committee-data)
    false
  )
)

;; Get compliance score for entity
(define-read-only (get-compliance-score (entity principal))
  (match (map-get? compliance-scores { entity: entity })
    scores
    (if (> (get review-count scores) u0)
      (/ (get total-score scores) (get review-count scores))
      u0
    )
    u0
  )
)

;; Check ethical compliance for subject
(define-read-only (check-compliance (subject-type (string-ascii 50)) (subject-id uint))
  (let
    (
      (reviews (get-reviews-for-subject subject-type subject-id))
    )
    (if (> (len reviews) u0)
      (calculate-average-compliance reviews)
      u0
    )
  )
)

;; Helper function to get reviews for subject (simplified)
(define-read-only (get-reviews-for-subject (subject-type (string-ascii 50)) (subject-id uint))
  ;; Simplified implementation - in practice would iterate through reviews
  (list u80) ;; Placeholder
)

;; Helper function to calculate average compliance
(define-read-only (calculate-average-compliance (scores (list 10 uint)))
  (if (> (len scores) u0)
    (/ (fold + scores u0) (len scores))
    u0
  )
)

;; Get total reviews count
(define-read-only (get-total-reviews)
  (- (var-get next-review-id) u1)
)

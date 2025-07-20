;; Crew Rotation Management Contract
;; Manages astronaut assignments, mission schedules, and crew operations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-CREW-NOT-FOUND (err u101))
(define-constant ERR-INVALID-SCHEDULE (err u102))
(define-constant ERR-CREW-UNAVAILABLE (err u103))
(define-constant ERR-INVALID-RATING (err u104))
(define-constant ERR-SCHEDULE-CONFLICT (err u105))

;; Data Variables
(define-data-var next-crew-id uint u1)
(define-data-var next-mission-id uint u1)
(define-data-var station-commander principal CONTRACT-OWNER)

;; Data Maps
(define-map crew-members
  { crew-id: uint }
  {
    name: (string-ascii 50),
    specialization: (string-ascii 30),
    certification-level: uint,
    health-status: uint,
    current-assignment: (optional uint),
    total-missions: uint,
    performance-rating: uint
  }
)

(define-map mission-schedules
  { mission-id: uint }
  {
    mission-name: (string-ascii 50),
    assigned-crew: (list 10 uint),
    start-time: uint,
    duration: uint,
    priority-level: uint,
    status: (string-ascii 20),
    required-specializations: (list 5 (string-ascii 30))
  }
)

(define-map crew-assignments
  { crew-id: uint, mission-id: uint }
  {
    role: (string-ascii 30),
    assignment-time: uint,
    completion-status: bool
  }
)

;; Authorization Functions
(define-private (is-authorized (caller principal))
  (or (is-eq caller CONTRACT-OWNER)
      (is-eq caller (var-get station-commander)))
)

;; Crew Management Functions
(define-public (register-crew-member
  (name (string-ascii 50))
  (specialization (string-ascii 30))
  (certification-level uint))
  (let ((crew-id (var-get next-crew-id)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= certification-level u1) (<= certification-level u5)) ERR-INVALID-RATING)

    (map-set crew-members
      { crew-id: crew-id }
      {
        name: name,
        specialization: specialization,
        certification-level: certification-level,
        health-status: u100,
        current-assignment: none,
        total-missions: u0,
        performance-rating: u5
      }
    )

    (var-set next-crew-id (+ crew-id u1))
    (ok crew-id)
  )
)

(define-public (update-crew-health (crew-id uint) (health-status uint))
  (let ((crew-data (unwrap! (map-get? crew-members { crew-id: crew-id }) ERR-CREW-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= health-status u100) ERR-INVALID-RATING)

    (map-set crew-members
      { crew-id: crew-id }
      (merge crew-data { health-status: health-status })
    )
    (ok true)
  )
)

(define-public (update-performance-rating (crew-id uint) (rating uint))
  (let ((crew-data (unwrap! (map-get? crew-members { crew-id: crew-id }) ERR-CREW-NOT-FOUND)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= rating u1) (<= rating u10)) ERR-INVALID-RATING)

    (map-set crew-members
      { crew-id: crew-id }
      (merge crew-data { performance-rating: rating })
    )
    (ok true)
  )
)

;; Mission Scheduling Functions
(define-public (create-mission-schedule
  (mission-name (string-ascii 50))
  (start-time uint)
  (duration uint)
  (priority-level uint)
  (required-specializations (list 5 (string-ascii 30))))
  (let ((mission-id (var-get next-mission-id)))
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> duration u0) ERR-INVALID-SCHEDULE)
    (asserts! (and (>= priority-level u1) (<= priority-level u5)) ERR-INVALID-RATING)

    (map-set mission-schedules
      { mission-id: mission-id }
      {
        mission-name: mission-name,
        assigned-crew: (list),
        start-time: start-time,
        duration: duration,
        priority-level: priority-level,
        status: "scheduled",
        required-specializations: required-specializations
      }
    )

    (var-set next-mission-id (+ mission-id u1))
    (ok mission-id)
  )
)

(define-public (assign-crew-to-mission (crew-id uint) (mission-id uint) (role (string-ascii 30)))
  (let (
    (crew-data (unwrap! (map-get? crew-members { crew-id: crew-id }) ERR-CREW-NOT-FOUND))
    (mission-data (unwrap! (map-get? mission-schedules { mission-id: mission-id }) ERR-INVALID-SCHEDULE))
  )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get health-status crew-data) u80) ERR-CREW-UNAVAILABLE)
    (asserts! (is-none (get current-assignment crew-data)) ERR-SCHEDULE-CONFLICT)

    ;; Update crew assignment
    (map-set crew-members
      { crew-id: crew-id }
      (merge crew-data { current-assignment: (some mission-id) })
    )

    ;; Record assignment details
    (map-set crew-assignments
      { crew-id: crew-id, mission-id: mission-id }
      {
        role: role,
        assignment-time: block-height,
        completion-status: false
      }
    )

    ;; Update mission crew list
    (let ((updated-crew (unwrap-panic (as-max-len? (append (get assigned-crew mission-data) crew-id) u10))))
      (map-set mission-schedules
        { mission-id: mission-id }
        (merge mission-data { assigned-crew: updated-crew })
      )
    )

    (ok true)
  )
)

(define-public (complete-mission-assignment (crew-id uint) (mission-id uint))
  (let (
    (crew-data (unwrap! (map-get? crew-members { crew-id: crew-id }) ERR-CREW-NOT-FOUND))
    (assignment-data (unwrap! (map-get? crew-assignments { crew-id: crew-id, mission-id: mission-id }) ERR-INVALID-SCHEDULE))
  )
    (asserts! (is-authorized tx-sender) ERR-NOT-AUTHORIZED)

    ;; Update assignment completion
    (map-set crew-assignments
      { crew-id: crew-id, mission-id: mission-id }
      (merge assignment-data { completion-status: true })
    )

    ;; Clear current assignment and increment mission count
    (map-set crew-members
      { crew-id: crew-id }
      (merge crew-data {
        current-assignment: none,
        total-missions: (+ (get total-missions crew-data) u1)
      })
    )

    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-crew-member (crew-id uint))
  (map-get? crew-members { crew-id: crew-id })
)

(define-read-only (get-mission-schedule (mission-id uint))
  (map-get? mission-schedules { mission-id: mission-id })
)

(define-read-only (get-crew-assignment (crew-id uint) (mission-id uint))
  (map-get? crew-assignments { crew-id: crew-id, mission-id: mission-id })
)

(define-read-only (get-available-crew)
  (var-get next-crew-id)
)

(define-read-only (is-crew-available (crew-id uint))
  (match (map-get? crew-members { crew-id: crew-id })
    crew-data (and
      (>= (get health-status crew-data) u80)
      (is-none (get current-assignment crew-data))
    )
    false
  )
)

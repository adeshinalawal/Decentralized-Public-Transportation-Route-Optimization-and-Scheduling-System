;; Multi-Modal Transportation Coordination Contract
;; Integrates bus, train, bike sharing, and ride-hailing services

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-SERVICE (err u501))
(define-constant ERR-SERVICE-NOT-FOUND (err u502))
(define-constant ERR-INVALID-SCHEDULE (err u503))
(define-constant ERR-TRANSFER-NOT-FOUND (err u504))

;; Data Variables
(define-data-var next-service-id uint u1)
(define-data-var next-transfer-id uint u1)

;; Data Maps
(define-map transportation-services
  { service-id: uint }
  {
    service-name: (string-ascii 50),
    service-type: (string-ascii 20),
    operator: principal,
    capacity: uint,
    operating-hours: { start: uint, end: uint },
    is-active: bool
  }
)

(define-map service-schedules
  { service-id: uint, route-id: uint }
  {
    departure-times: (list 24 uint),
    frequency: uint,
    travel-time: uint,
    reliability-score: uint
  }
)

(define-map transfer-points
  { transfer-id: uint }
  {
    location: (string-ascii 100),
    connected-services: (list 10 uint),
    transfer-time: uint,
    accessibility-rating: uint,
    last-updated: uint
  }
)

(define-map coordination-rules
  { service-id-1: uint, service-id-2: uint }
  {
    sync-required: bool,
    max-wait-time: uint,
    priority-service: uint,
    coordination-type: (string-ascii 30)
  }
)

(define-map authorized-coordinators
  { coordinator: principal }
  { is-authorized: bool }
)

;; Authorization Functions
(define-public (authorize-coordinator (coordinator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-coordinators { coordinator: coordinator } { is-authorized: true }))
  )
)

;; Service Management
(define-public (register-service (service-name (string-ascii 50)) (service-type (string-ascii 20)) (capacity uint) (start-hour uint) (end-hour uint))
  (let ((service-id (var-get next-service-id)))
    (asserts! (is-authorized-coordinator tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (< start-hour u24) (< end-hour u24) (< start-hour end-hour)) ERR-INVALID-SCHEDULE)
    (map-set transportation-services
      { service-id: service-id }
      {
        service-name: service-name,
        service-type: service-type,
        operator: tx-sender,
        capacity: capacity,
        operating-hours: { start: start-hour, end: end-hour },
        is-active: true
      }
    )
    (var-set next-service-id (+ service-id u1))
    (ok service-id)
  )
)

(define-public (update-service-schedule (service-id uint) (route-id uint) (departure-times (list 24 uint)) (frequency uint) (travel-time uint))
  (begin
    (asserts! (is-authorized-coordinator tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-valid-service service-id) ERR-SERVICE-NOT-FOUND)
    (asserts! (and (> frequency u0) (> travel-time u0)) ERR-INVALID-SCHEDULE)
    (map-set service-schedules
      { service-id: service-id, route-id: route-id }
      {
        departure-times: departure-times,
        frequency: frequency,
        travel-time: travel-time,
        reliability-score: u85
      }
    )
    (ok true)
  )
)

;; Transfer Point Management
(define-public (create-transfer-point (location (string-ascii 100)) (connected-services (list 10 uint)) (transfer-time uint) (accessibility-rating uint))
  (let ((transfer-id (var-get next-transfer-id)))
    (asserts! (is-authorized-coordinator tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (> transfer-time u0) (<= accessibility-rating u5)) ERR-INVALID-SERVICE)
    (map-set transfer-points
      { transfer-id: transfer-id }
      {
        location: location,
        connected-services: connected-services,
        transfer-time: transfer-time,
        accessibility-rating: accessibility-rating,
        last-updated: block-height
      }
    )
    (var-set next-transfer-id (+ transfer-id u1))
    (ok transfer-id)
  )
)

;; Coordination Rules
(define-public (set-coordination-rule (service-id-1 uint) (service-id-2 uint) (sync-required bool) (max-wait-time uint) (coordination-type (string-ascii 30)))
  (let ((priority-service (if sync-required service-id-1 service-id-2)))
    (asserts! (is-authorized-coordinator tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (is-valid-service service-id-1) (is-valid-service service-id-2)) ERR-SERVICE-NOT-FOUND)
    (map-set coordination-rules
      { service-id-1: service-id-1, service-id-2: service-id-2 }
      {
        sync-required: sync-required,
        max-wait-time: max-wait-time,
        priority-service: priority-service,
        coordination-type: coordination-type
      }
    )
    (ok true)
  )
)

;; Query Functions
(define-read-only (get-service-info (service-id uint))
  (map-get? transportation-services { service-id: service-id })
)

(define-read-only (get-service-schedule (service-id uint) (route-id uint))
  (map-get? service-schedules { service-id: service-id, route-id: route-id })
)

(define-read-only (get-transfer-point (transfer-id uint))
  (map-get? transfer-points { transfer-id: transfer-id })
)

(define-read-only (get-coordination-rule (service-id-1 uint) (service-id-2 uint))
  (map-get? coordination-rules { service-id-1: service-id-1, service-id-2: service-id-2 })
)

(define-read-only (calculate-journey-time (service-id uint) (route-id uint) (transfer-id (optional uint)))
  (match (get-service-schedule service-id route-id)
    schedule
    (let ((base-time (get travel-time schedule))
          (transfer-time (match transfer-id
                           tid (match (get-transfer-point tid)
                                 tp (get transfer-time tp)
                                 u0)
                           u0)))
      (ok (+ base-time transfer-time)))
    (err ERR-SERVICE-NOT-FOUND)
  )
)

(define-read-only (get-optimal-connection (service-id-1 uint) (service-id-2 uint))
  (match (get-coordination-rule service-id-1 service-id-2)
    rule
    (ok {
      sync-required: (get sync-required rule),
      max-wait: (get max-wait-time rule),
      coordination-score: (calculate-coordination-score service-id-1 service-id-2)
    })
    (ok {
      sync-required: false,
      max-wait: u15,
      coordination-score: u50
    })
  )
)

;; Helper Functions
(define-private (is-authorized-coordinator (coordinator principal))
  (default-to false (get is-authorized (map-get? authorized-coordinators { coordinator: coordinator })))
)

(define-private (is-valid-service (service-id uint))
  (match (map-get? transportation-services { service-id: service-id })
    service (get is-active service)
    false
  )
)

(define-private (calculate-coordination-score (service-id-1 uint) (service-id-2 uint))
  (match (get-coordination-rule service-id-1 service-id-2)
    rule
    (let ((sync-bonus (if (get sync-required rule) u30 u0))
          (wait-penalty (/ (get max-wait-time rule) u2)))
      (+ u50 sync-bonus (- u0 wait-penalty)))
    u50
  )
)

;; Initialize contract owner as authorized coordinator
(map-set authorized-coordinators { coordinator: CONTRACT-OWNER } { is-authorized: true })

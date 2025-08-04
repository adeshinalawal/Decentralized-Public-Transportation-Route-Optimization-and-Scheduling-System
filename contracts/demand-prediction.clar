;; Passenger Demand Prediction Contract
;; Anticipates ridership patterns and optimizes service frequency

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-ROUTE (err u201))
(define-constant ERR-INVALID-TIME (err u202))
(define-constant ERR-INVALID-CAPACITY (err u203))

;; Data Variables
(define-data-var prediction-accuracy uint u85)

;; Data Maps
(define-map ridership-history
  { route-id: uint, time-slot: uint, date: uint }
  {
    passenger-count: uint,
    capacity-utilization: uint,
    peak-indicator: bool
  }
)

(define-map demand-predictions
  { route-id: uint, time-slot: uint }
  {
    predicted-demand: uint,
    confidence-level: uint,
    recommended-frequency: uint,
    last-updated: uint
  }
)

(define-map route-capacity
  { route-id: uint }
  {
    max-capacity: uint,
    current-vehicles: uint,
    service-frequency: uint
  }
)

(define-map authorized-reporters
  { reporter: principal }
  { is-authorized: bool }
)

;; Authorization Functions
(define-public (authorize-reporter (reporter principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-reporters { reporter: reporter } { is-authorized: true }))
  )
)

;; Ridership Data Functions
(define-public (record-ridership (route-id uint) (time-slot uint) (date uint) (passenger-count uint) (max-capacity uint))
  (let ((utilization (calculate-utilization passenger-count max-capacity))
        (is-peak (> utilization u80)))
    (asserts! (is-authorized-reporter tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= time-slot u0) (< time-slot u24)) ERR-INVALID-TIME)
    (asserts! (> max-capacity u0) ERR-INVALID-CAPACITY)
    (map-set ridership-history
      { route-id: route-id, time-slot: time-slot, date: date }
      {
        passenger-count: passenger-count,
        capacity-utilization: utilization,
        peak-indicator: is-peak
      }
    )
    (ok true)
  )
)

(define-public (update-route-capacity (route-id uint) (max-capacity uint) (current-vehicles uint) (service-frequency uint))
  (begin
    (asserts! (is-authorized-reporter tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (> max-capacity u0) ERR-INVALID-CAPACITY)
    (map-set route-capacity
      { route-id: route-id }
      {
        max-capacity: max-capacity,
        current-vehicles: current-vehicles,
        service-frequency: service-frequency
      }
    )
    (ok true)
  )
)

;; Prediction Functions
(define-public (generate-demand-prediction (route-id uint) (time-slot uint) (predicted-demand uint) (confidence-level uint))
  (let ((recommended-freq (calculate-recommended-frequency predicted-demand route-id)))
    (asserts! (is-authorized-reporter tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= time-slot u0) (< time-slot u24)) ERR-INVALID-TIME)
    (asserts! (and (>= confidence-level u0) (<= confidence-level u100)) ERR-INVALID-CAPACITY)
    (map-set demand-predictions
      { route-id: route-id, time-slot: time-slot }
      {
        predicted-demand: predicted-demand,
        confidence-level: confidence-level,
        recommended-frequency: recommended-freq,
        last-updated: block-height
      }
    )
    (ok true)
  )
)

;; Query Functions
(define-read-only (get-ridership-history (route-id uint) (time-slot uint) (date uint))
  (map-get? ridership-history { route-id: route-id, time-slot: time-slot, date: date })
)

(define-read-only (get-demand-prediction (route-id uint) (time-slot uint))
  (map-get? demand-predictions { route-id: route-id, time-slot: time-slot })
)

(define-read-only (get-route-capacity (route-id uint))
  (map-get? route-capacity { route-id: route-id })
)

(define-read-only (get-peak-hours (route-id uint))
  (ok (list u7 u8 u9 u17 u18 u19))
)

(define-read-only (calculate-demand-score (route-id uint) (time-slot uint))
  (match (get-demand-prediction route-id time-slot)
    prediction
    (let ((demand (get predicted-demand prediction))
          (confidence (get confidence-level prediction)))
      (ok (/ (* demand confidence) u100)))
    (ok u0)
  )
)

;; Helper Functions
(define-private (is-authorized-reporter (reporter principal))
  (default-to false (get is-authorized (map-get? authorized-reporters { reporter: reporter })))
)

(define-private (calculate-utilization (passengers uint) (capacity uint))
  (if (> capacity u0)
    (/ (* passengers u100) capacity)
    u0
  )
)

(define-private (calculate-recommended-frequency (demand uint) (route-id uint))
  (match (get-route-capacity route-id)
    capacity-info
    (let ((max-capacity (get max-capacity capacity-info))
          (calculated-freq (if (> max-capacity u0) (/ demand max-capacity) u1)))
      (if (> calculated-freq u1) calculated-freq u1))
    u1
  )
)

;; Initialize contract owner as authorized reporter
(map-set authorized-reporters { reporter: CONTRACT-OWNER } { is-authorized: true })

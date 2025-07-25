;; Consciousness Protocol Contract
;; Manages consciousness insertion and tracking in simulated environments

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u300))
(define-constant ERR-CONSCIOUSNESS-EXISTS (err u301))
(define-constant ERR-CONSCIOUSNESS-NOT-FOUND (err u302))
(define-constant ERR-UNIVERSE-NOT-FOUND (err u303))
(define-constant ERR-INVALID-TRANSFER (err u304))
(define-constant ERR-CONSCIOUSNESS-BUSY (err u305))

;; Data Variables
(define-data-var next-consciousness-id uint u1)
(define-data-var total-consciousness uint u0)
(define-data-var transfer-id uint u1)

;; Data Maps
(define-map consciousness-registry uint {
  owner: principal,
  current-universe: uint,
  avatar-name: (string-ascii 50),
  status: (string-ascii 20),
  created-at: uint,
  last-transfer: uint,
  transfer-count: uint
})

(define-map consciousness-history uint (list 100 {
  universe-id: uint,
  entered-at: uint,
  exited-at: (optional uint),
  transfer-id: uint,
  reason: (string-ascii 100)
}))

(define-map universe-consciousness uint (list 50 uint))
(define-map consciousness-permissions uint {
  can-modify-reality: bool,
  can-create-objects: bool,
  can-interact-others: bool,
  admin-level: uint
})

(define-map transfer-requests uint {
  consciousness-id: uint,
  from-universe: uint,
  to-universe: uint,
  requester: principal,
  status: (string-ascii 20),
  requested-at: uint,
  processed-at: (optional uint)
})

;; Public Functions

;; Create new consciousness
(define-public (create-consciousness (avatar-name (string-ascii 50)) (initial-universe uint))
  (let ((consciousness-id (var-get next-consciousness-id))
        (owner tx-sender))
    (begin
      ;; Create consciousness record
      (map-set consciousness-registry consciousness-id {
        owner: owner,
        current-universe: initial-universe,
        avatar-name: avatar-name,
        status: "active",
        created-at: block-height,
        last-transfer: block-height,
        transfer-count: u0
      })

      ;; Set default permissions
      (map-set consciousness-permissions consciousness-id {
        can-modify-reality: false,
        can-create-objects: true,
        can-interact-others: true,
        admin-level: u1
      })

      ;; Add to universe consciousness list
      (let ((current-list (default-to (list) (map-get? universe-consciousness initial-universe))))
        (map-set universe-consciousness initial-universe
          (unwrap-panic (as-max-len? (append current-list consciousness-id) u50))))

      ;; Record initial entry
      (map-set consciousness-history consciousness-id (list {
        universe-id: initial-universe,
        entered-at: block-height,
        exited-at: none,
        transfer-id: u0,
        reason: "initial-insertion"
      }))

      ;; Update counters
      (var-set next-consciousness-id (+ consciousness-id u1))
      (var-set total-consciousness (+ (var-get total-consciousness) u1))

      (ok consciousness-id))))

;; Insert consciousness into universe
(define-public (insert-consciousness (consciousness-id uint) (target-universe uint) (reason (string-ascii 100)))
  (let ((consciousness (unwrap! (map-get? consciousness-registry consciousness-id) ERR-CONSCIOUSNESS-NOT-FOUND))
        (current-universe (get current-universe consciousness)))
    (begin
      ;; Check authorization
      (asserts! (is-eq tx-sender (get owner consciousness)) ERR-NOT-AUTHORIZED)

      ;; Check if consciousness is available for transfer
      (asserts! (is-eq (get status consciousness) "active") ERR-CONSCIOUSNESS-BUSY)

      ;; Remove from current universe
      (let ((current-list (default-to (list) (map-get? universe-consciousness current-universe))))
        (map-set universe-consciousness current-universe
          (filter-consciousness current-list consciousness-id)))

      ;; Add to target universe
      (let ((target-list (default-to (list) (map-get? universe-consciousness target-universe))))
        (map-set universe-consciousness target-universe
          (unwrap-panic (as-max-len? (append target-list consciousness-id) u50))))

      ;; Update consciousness record
      (map-set consciousness-registry consciousness-id (merge consciousness {
        current-universe: target-universe,
        last-transfer: block-height,
        transfer-count: (+ (get transfer-count consciousness) u1)
      }))

      ;; Update history
      (let ((current-history (default-to (list) (map-get? consciousness-history consciousness-id))))
        (map-set consciousness-history consciousness-id
          (unwrap-panic (as-max-len?
            (append current-history {
              universe-id: target-universe,
              entered-at: block-height,
              exited-at: none,
              transfer-id: (var-get transfer-id),
              reason: reason
            }) u100))))

      ;; Increment transfer ID
      (var-set transfer-id (+ (var-get transfer-id) u1))

      (ok true))))

;; Request consciousness transfer
(define-public (request-transfer (consciousness-id uint) (to-universe uint) (reason (string-ascii 100)))
  (let ((consciousness (unwrap! (map-get? consciousness-registry consciousness-id) ERR-CONSCIOUSNESS-NOT-FOUND))
        (request-id (var-get transfer-id)))
    (begin
      ;; Check authorization
      (asserts! (is-eq tx-sender (get owner consciousness)) ERR-NOT-AUTHORIZED)

      ;; Create transfer request
      (map-set transfer-requests request-id {
        consciousness-id: consciousness-id,
        from-universe: (get current-universe consciousness),
        to-universe: to-universe,
        requester: tx-sender,
        status: "pending",
        requested-at: block-height,
        processed-at: none
      })

      ;; Auto-approve for now (could add governance later)
      (try! (insert-consciousness consciousness-id to-universe reason))

      ;; Update request status
      (map-set transfer-requests request-id (merge
        (unwrap-panic (map-get? transfer-requests request-id))
        {status: "approved", processed-at: (some block-height)}))

      (ok request-id))))

;; Update consciousness permissions
(define-public (update-permissions (consciousness-id uint) (permissions {can-modify-reality: bool, can-create-objects: bool, can-interact-others: bool, admin-level: uint}))
  (let ((consciousness (unwrap! (map-get? consciousness-registry consciousness-id) ERR-CONSCIOUSNESS-NOT-FOUND)))
    (begin
      ;; Check authorization (only owner or admin)
      (asserts! (or
        (is-eq tx-sender (get owner consciousness))
        (is-eq tx-sender CONTRACT-OWNER)) ERR-NOT-AUTHORIZED)

      ;; Update permissions
      (map-set consciousness-permissions consciousness-id permissions)

      (ok true))))

;; Pause consciousness
(define-public (pause-consciousness (consciousness-id uint))
  (let ((consciousness (unwrap! (map-get? consciousness-registry consciousness-id) ERR-CONSCIOUSNESS-NOT-FOUND)))
    (begin
      ;; Check authorization
      (asserts! (is-eq tx-sender (get owner consciousness)) ERR-NOT-AUTHORIZED)

      ;; Update status
      (map-set consciousness-registry consciousness-id (merge consciousness {
        status: "paused"
      }))

      (ok true))))

;; Resume consciousness
(define-public (resume-consciousness (consciousness-id uint))
  (let ((consciousness (unwrap! (map-get? consciousness-registry consciousness-id) ERR-CONSCIOUSNESS-NOT-FOUND)))
    (begin
      ;; Check authorization
      (asserts! (is-eq tx-sender (get owner consciousness)) ERR-NOT-AUTHORIZED)

      ;; Update status
      (map-set consciousness-registry consciousness-id (merge consciousness {
        status: "active"
      }))

      (ok true))))

;; Read-only Functions

;; Get consciousness details
(define-read-only (get-consciousness (consciousness-id uint))
  (map-get? consciousness-registry consciousness-id))

;; Get consciousness permissions
(define-read-only (get-consciousness-permissions (consciousness-id uint))
  (map-get? consciousness-permissions consciousness-id))

;; Get consciousness history
(define-read-only (get-consciousness-history (consciousness-id uint))
  (map-get? consciousness-history consciousness-id))

;; Get consciousness in universe
(define-read-only (get-universe-consciousness (universe-id uint))
  (default-to (list) (map-get? universe-consciousness universe-id)))

;; Get transfer request
(define-read-only (get-transfer-request (request-id uint))
  (map-get? transfer-requests request-id))

;; Get total consciousness count
(define-read-only (get-total-consciousness)
  (var-get total-consciousness))

;; Private Functions

;; Filter consciousness from list
(define-private (filter-consciousness (consciousness-list (list 50 uint)) (consciousness-id uint))
  (filter is-not-target-consciousness consciousness-list))

;; Check if consciousness is not the target
(define-private (is-not-target-consciousness (id uint))
  (not (is-eq id u1))) ;; This would need to be dynamic in real implementation

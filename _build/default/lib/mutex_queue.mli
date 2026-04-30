(** Simple mutex-protected queue baseline.

    A direct lock-based queue where every operation acquires a mutex.
    This is the simplest synchronization approach and serves as a baseline
    to demonstrate the overhead that flat combining optimizes away. *)

type 'a t

val create : unit -> 'a t
(** Create a new mutex-protected queue. *)

val enqueue : 'a t -> 'a -> unit
(** Enqueue an element. Acquires mutex for entire operation. *)

val dequeue : 'a t -> 'a option
(** Dequeue an element, or None if queue is empty.
    Non-blocking; always returns immediately. *)

val length : 'a t -> int
(** Return queue length (must acquire lock). *)

val is_empty : 'a t -> bool
(** Check if queue is empty (must acquire lock). *)

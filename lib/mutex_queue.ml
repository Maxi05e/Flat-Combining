(** Simple mutex-protected queue for baseline comparison.
    Direct lock-based implementation without batching or blocking.
    Used as a performance baseline against flat combining and blocking queues. *)

type 'a t = {
  q : 'a Queue.t;
  lock : Mutex.t;
}

let create () =
  { q = Queue.create (); lock = Mutex.create () }

let enqueue t value =
  Mutex.lock t.lock;
  Queue.add value t.q;
  Mutex.unlock t.lock

let dequeue t =
  Mutex.lock t.lock;
  let result =
    try Some (Queue.take t.q) with Queue.Empty -> None
  in
  Mutex.unlock t.lock;
  result

let length t =
  Mutex.lock t.lock;
  let len = Queue.length t.q in
  Mutex.unlock t.lock;
  len

let is_empty t =
  Mutex.lock t.lock;
  let empty = Queue.is_empty t.q in
  Mutex.unlock t.lock;
  empty

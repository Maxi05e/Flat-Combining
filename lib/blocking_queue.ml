(** Lock-based queue with condition variables (blocking version)

    This queue uses condition variables to wait when full/empty.
    Instead of raising exceptions or spin-waiting, threads block
    and are woken up when the condition changes.
*)

type 'a t = {
	items : 'a option array;
	capacity : int;
	mutable head : int;
	mutable tail : int;
	lock : Mutex.t;
	not_empty : Condition.t;
	not_full : Condition.t;
}

let create capacity =
	if capacity <= 0 then invalid_arg "Blocking_queue.create: capacity must be positive";
	{
		items = Array.make capacity None;
		capacity;
		head = 0;
		tail = 0;
		lock = Mutex.create ();
		not_empty = Condition.create ();
		not_full = Condition.create ();
	}

let enq q x =
	Mutex.lock q.lock;
	Fun.protect ~finally:(fun () -> Mutex.unlock q.lock) @@ fun () ->
	while q.tail - q.head = q.capacity do
		Condition.wait q.not_full q.lock
	done;
	q.items.(q.tail mod q.capacity) <- Some x;
	q.tail <- q.tail + 1;
	Condition.signal q.not_empty

let deq q =
	Mutex.lock q.lock;
	Fun.protect ~finally:(fun () -> Mutex.unlock q.lock) @@ fun () ->
	while q.tail = q.head do
		Condition.wait q.not_empty q.lock
	done;
	match q.items.(q.head mod q.capacity) with
	| None -> assert false
	| Some x ->
		q.items.(q.head mod q.capacity) <- None;
		q.head <- q.head + 1;
		Condition.signal q.not_full;
		x

let enqueue = enq

let dequeue = deq

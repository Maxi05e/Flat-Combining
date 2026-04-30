type state = int Queue.t

type op =
	| Enq of int
	| Deq

type result = int option

let initial_state () : state = Queue.create ()

let apply state = function
	| Enq value ->
		Queue.add value state;
		state, None
	| Deq ->
		if Queue.is_empty state then state, None
		else state, Some (Queue.take state)

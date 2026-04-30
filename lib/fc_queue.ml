module Wrapper = Fc_wrapper.Make (Types)

type t = Wrapper.t
type stats = Wrapper.stats

let create ?(slots = 8) () = Wrapper.create ~slots ()

let enqueue t value =
	let _ = Wrapper.invoke t ~op:(Types.Enq value) in
	()

let dequeue t = Wrapper.invoke t ~op:Types.Deq

let reset_stats t = Wrapper.reset_stats t

let get_stats t = Wrapper.get_stats t

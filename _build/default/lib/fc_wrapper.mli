module type SEQUENTIAL = sig
	type state
	type op
	type result

	val initial_state : unit -> state
	val apply : state -> op -> state * result
end

module Make (Q : SEQUENTIAL) : sig
	type t
	type stats = {
		combine_cycles : int;
		combined_ops : int;
	}

	val create : slots:int -> unit -> t
	val invoke : t -> op:Q.op -> Q.result
	val reset_stats : t -> unit
	val get_stats : t -> stats
end

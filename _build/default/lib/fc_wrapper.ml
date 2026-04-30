module type SEQUENTIAL = sig
	type state
	type op
	type result

	val initial_state : unit -> state
	val apply : state -> op -> state * result
end

module Make (Q : SEQUENTIAL) = struct
	type request =
		| Empty
		| Pending of Q.op
		| Completed of Q.result

	type slot = {
		request : request Atomic.t;
	}

	type t = {
		combiner_active : bool Atomic.t;
		slot_alloc_mutex : Mutex.t;
		mutable next_slot : int;
		slot_key : int option Domain.DLS.key;
		slots : slot array;
		mutable state : Q.state;
		combine_cycles_counter : int Atomic.t;
		combined_ops_counter : int Atomic.t;
	}

	type stats = {
		combine_cycles : int;
		combined_ops : int;
	}

	let make_slot () = { request = Atomic.make Empty }

	let create ~slots () =
		if slots <= 0 then invalid_arg "Fc_wrapper.create: slots must be positive";
		{
			combiner_active = Atomic.make false;
			slot_alloc_mutex = Mutex.create ();
			next_slot = 0;
			slot_key = Domain.DLS.new_key (fun () -> None);
			slots = Array.init slots (fun _ -> make_slot ());
			state = Q.initial_state ();
			combine_cycles_counter = Atomic.make 0;
			combined_ops_counter = Atomic.make 0;
		}

	let acquire_slot t =
		match Domain.DLS.get t.slot_key with
		| Some slot_index -> slot_index
		| None ->
			Mutex.lock t.slot_alloc_mutex;
			let slot_index =
				if t.next_slot >= Array.length t.slots then (
					Mutex.unlock t.slot_alloc_mutex;
					invalid_arg "Fc_wrapper.invoke: not enough publication slots")
				else
					let slot_index = t.next_slot in
					t.next_slot <- t.next_slot + 1;
					slot_index
			in
			Mutex.unlock t.slot_alloc_mutex;
			Domain.DLS.set t.slot_key (Some slot_index);
			slot_index

	let publish t slot_index op =
		let slot = t.slots.(slot_index) in
		if not (Atomic.compare_and_set slot.request Empty (Pending op)) then
			invalid_arg "Fc_wrapper.publish: slot was not empty"

	let take_result slot =
		match Atomic.get slot.request with
		| Completed value as current ->
			if Atomic.compare_and_set slot.request current Empty then Some value else None
		| _ -> None

	let fulfill slot result =
		let rec loop () =
			match Atomic.get slot.request with
			| Pending _ as current ->
				if Atomic.compare_and_set slot.request current (Completed result) then () else loop ()
			| Empty | Completed _ -> ()
		in
		loop ()

	let combine_once t =
		let progress = ref false in
		let batch_ops = ref 0 in
		for slot_index = 0 to Array.length t.slots - 1 do
			match Atomic.get t.slots.(slot_index).request with
			| Pending op ->
				let new_state, result = Q.apply t.state op in
				t.state <- new_state;
				fulfill t.slots.(slot_index) result;
				progress := true;
				incr batch_ops
			| Empty | Completed _ -> ()
		done;
		if !batch_ops > 0 then (
			ignore (Atomic.fetch_and_add t.combine_cycles_counter 1);
			ignore (Atomic.fetch_and_add t.combined_ops_counter !batch_ops));
		!progress

	let rec combine_until_stable t =
		if combine_once t then combine_until_stable t

	let rec wait_for_result t slot_index =
		let slot = t.slots.(slot_index) in
		match take_result slot with
		| Some value -> value
		| None ->
			if Atomic.compare_and_set t.combiner_active false true then (
				combine_until_stable t;
				Atomic.set t.combiner_active false)
			else Domain.cpu_relax ();
			wait_for_result t slot_index

	let invoke t ~op =
		let slot_index = acquire_slot t in
		publish t slot_index op;
		wait_for_result t slot_index

	let reset_stats t =
		Atomic.set t.combine_cycles_counter 0;
		Atomic.set t.combined_ops_counter 0

	let get_stats t =
		{
			combine_cycles = Atomic.get t.combine_cycles_counter;
			combined_ops = Atomic.get t.combined_ops_counter;
		}
end
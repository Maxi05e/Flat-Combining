let now = Unix.gettimeofday

let split_counts total parts =
	let base = total / parts in
	let rem = total mod parts in
	Array.init parts (fun i -> if i < rem then base + 1 else base)

type mix = {
	label : string;
	enq_pct : int;
}

type workload = {
	producer_threads : int;
	consumer_threads : int;
	total_dynamic_enq : int;
	total_dynamic_deq : int;
	prefill : int;
	producer_targets : int array;
	consumer_targets : int array;
}

type result = {
	seconds : float;
	total_ops : int;
	avg_batch_size : float option;
}

let calc_workload ~threads ~ops_per_thread ~enq_pct =
	let total_dynamic_ops = threads * ops_per_thread in
	let total_dynamic_enq = max 1 ((total_dynamic_ops * enq_pct) / 100) in
	let total_dynamic_deq = max 1 (total_dynamic_ops - total_dynamic_enq) in
	let prefill = max 0 (total_dynamic_deq - total_dynamic_enq) in
	let producer_threads = max 1 ((threads * enq_pct) / 100) in
	let consumer_threads = max 1 (threads - producer_threads) in
	let producer_targets = split_counts total_dynamic_enq producer_threads in
	let consumer_targets = split_counts total_dynamic_deq consumer_threads in
	{
		producer_threads;
		consumer_threads;
		total_dynamic_enq;
		total_dynamic_deq;
		prefill;
		producer_targets;
		consumer_targets;
	}

let benchmark_fc_mix ~threads ~ops_per_thread ~enq_pct =
	let wl = calc_workload ~threads ~ops_per_thread ~enq_pct in
	let q = Flat_combining.Fc_queue.create ~slots:(threads + 1) () in
	for i = 1 to wl.prefill do
		Flat_combining.Fc_queue.enqueue q (-i)
	done;
	Flat_combining.Fc_queue.reset_stats q;
	let start = now () in
	let producer_domains =
		Array.init wl.producer_threads (fun tid ->
			Domain.spawn (fun () ->
				let target = wl.producer_targets.(tid) in
				for i = 1 to target do
					Flat_combining.Fc_queue.enqueue q (tid * ops_per_thread + i)
				done))
	in
	let consumer_domains =
		Array.init wl.consumer_threads (fun tid ->
			Domain.spawn (fun () ->
				let target = wl.consumer_targets.(tid) in
				let rec loop got =
					if got = target then ()
					else
						match Flat_combining.Fc_queue.dequeue q with
						| Some _ -> loop (got + 1)
						| None -> Domain.cpu_relax (); loop got
				in
				loop 0))
	in
	Array.iter (fun d -> ignore (Domain.join d)) producer_domains;
	Array.iter (fun d -> ignore (Domain.join d)) consumer_domains;
	let seconds = now () -. start in
	let stats = Flat_combining.Fc_queue.get_stats q in
	let avg_batch_size =
		if stats.combine_cycles = 0 then None
		else Some (float_of_int stats.combined_ops /. float_of_int stats.combine_cycles)
	in
	{ seconds; total_ops = wl.total_dynamic_enq + wl.total_dynamic_deq; avg_batch_size }

let benchmark_mutex_mix ~threads ~ops_per_thread ~enq_pct =
	let wl = calc_workload ~threads ~ops_per_thread ~enq_pct in
	let q = Flat_combining.Mutex_queue.create () in
	for i = 1 to wl.prefill do
		Flat_combining.Mutex_queue.enqueue q (-i)
	done;
	let start = now () in
	let producer_domains =
		Array.init wl.producer_threads (fun tid ->
			Domain.spawn (fun () ->
				let target = wl.producer_targets.(tid) in
				for i = 1 to target do
					Flat_combining.Mutex_queue.enqueue q (tid * ops_per_thread + i)
				done))
	in
	let consumer_domains =
		Array.init wl.consumer_threads (fun tid ->
			Domain.spawn (fun () ->
				let target = wl.consumer_targets.(tid) in
				let rec loop got =
					if got = target then ()
					else
						match Flat_combining.Mutex_queue.dequeue q with
						| Some _ -> loop (got + 1)
						| None -> Domain.cpu_relax (); loop got
				in
				loop 0))
	in
	Array.iter (fun d -> ignore (Domain.join d)) producer_domains;
	Array.iter (fun d -> ignore (Domain.join d)) consumer_domains;
	{ seconds = now () -. start; total_ops = wl.total_dynamic_enq + wl.total_dynamic_deq; avg_batch_size = None }

let benchmark_blocking_mix ~threads ~ops_per_thread ~enq_pct =
	let wl = calc_workload ~threads ~ops_per_thread ~enq_pct in
	let q = Flat_combining.Blocking_queue.create (wl.prefill + wl.total_dynamic_enq + 8) in
	for i = 1 to wl.prefill do
		Flat_combining.Blocking_queue.enqueue q (-i)
	done;
	let start = now () in
	let producer_domains =
		Array.init wl.producer_threads (fun tid ->
			Domain.spawn (fun () ->
				let target = wl.producer_targets.(tid) in
				for i = 1 to target do
					Flat_combining.Blocking_queue.enqueue q (tid * ops_per_thread + i)
				done))
	in
	let consumer_domains =
		Array.init wl.consumer_threads (fun tid ->
			Domain.spawn (fun () ->
				let target = wl.consumer_targets.(tid) in
				for _ = 1 to target do
					ignore (Flat_combining.Blocking_queue.dequeue q)
				done))
	in
	Array.iter (fun d -> ignore (Domain.join d)) producer_domains;
	Array.iter (fun d -> ignore (Domain.join d)) consumer_domains;
	{ seconds = now () -. start; total_ops = wl.total_dynamic_enq + wl.total_dynamic_deq; avg_batch_size = None }

let print_result ~name ~threads ~ops_per_thread ~mix result =
	let throughput = float_of_int result.total_ops /. result.seconds in
	match result.avg_batch_size with
	| Some batch ->
		Printf.printf
			"%s,threads=%d,ops_per_thread=%d,mix=%s,time=%.6fs,total_ops=%d,throughput=%.2f ops/s,avg_batch_size=%.3f\n%!"
			name threads ops_per_thread mix result.seconds result.total_ops throughput batch
	| None ->
		Printf.printf
			"%s,threads=%d,ops_per_thread=%d,mix=%s,time=%.6fs,total_ops=%d,throughput=%.2f ops/s\n%!"
			name threads ops_per_thread mix result.seconds result.total_ops throughput

let run_matrix ~ops_per_thread =
	(* expanded thread counts to explore higher contention levels *)
	let thread_counts = [ 2; 4; 6; 8; 12; 16; 24; 32 ] in
	let mixes =
		[ { label = "enqueue_heavy_80_20"; enq_pct = 80 };
		  { label = "balanced_50_50"; enq_pct = 50 };
		  { label = "dequeue_heavy_20_80"; enq_pct = 20 } ]
	in
	List.iter
		(fun threads ->
			List.iter
				(fun mix ->
					let fc = benchmark_fc_mix ~threads ~ops_per_thread ~enq_pct:mix.enq_pct in
					let mx = benchmark_mutex_mix ~threads ~ops_per_thread ~enq_pct:mix.enq_pct in
					let bq = benchmark_blocking_mix ~threads ~ops_per_thread ~enq_pct:mix.enq_pct in
					print_result ~name:"fc_queue" ~threads ~ops_per_thread ~mix:mix.label fc;
					print_result ~name:"mutex_queue" ~threads ~ops_per_thread ~mix:mix.label mx;
					print_result ~name:"blocking_queue" ~threads ~ops_per_thread ~mix:mix.label bq)
				mixes)
		thread_counts

let () =
	let ops_per_thread = if Array.length Sys.argv > 1 then int_of_string Sys.argv.(1) else 20_000 in
	run_matrix ~ops_per_thread

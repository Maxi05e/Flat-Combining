let assert_equal_int_option label expected actual =
	Printf.printf "[check] %s -> expected=%s actual=%s\n%!" label
		(match expected with None -> "None" | Some value -> Printf.sprintf "Some %d" value)
		(match actual with None -> "None" | Some value -> Printf.sprintf "Some %d" value);
	if expected <> actual then
		failwith
			(Printf.sprintf "%s expected %s but got %s" label
				(match expected with None -> "None" | Some value -> Printf.sprintf "Some %d" value)
				(match actual with None -> "None" | Some value -> Printf.sprintf "Some %d" value))

let sequential_test () =
	print_endline "[test] sequential_test: start";
	let queue = Flat_combining.Fc_queue.create ~slots:4 () in
	print_endline "[test] sequential_test: enqueue 1,2,3";
	Flat_combining.Fc_queue.enqueue queue 1;
	Flat_combining.Fc_queue.enqueue queue 2;
	Flat_combining.Fc_queue.enqueue queue 3;
	print_endline "[test] sequential_test: dequeue checks";
	assert_equal_int_option "deq1" (Some 1) (Flat_combining.Fc_queue.dequeue queue);
	assert_equal_int_option "deq2" (Some 2) (Flat_combining.Fc_queue.dequeue queue);
	assert_equal_int_option "deq3" (Some 3) (Flat_combining.Fc_queue.dequeue queue);
	assert_equal_int_option "deq4" None (Flat_combining.Fc_queue.dequeue queue);
	print_endline "[test] sequential_test: passed"

let concurrent_enq_test () =
	print_endline "[test] concurrent_enq_test: start";
	let queue = Flat_combining.Fc_queue.create ~slots:8 () in
	print_endline "[test] concurrent_enq_test: launch 4 domains, 25 enqueues each";
	let domains =
		Array.init 4 (fun index ->
			Domain.spawn (fun () ->
				for value = 1 to 25 do
					Flat_combining.Fc_queue.enqueue queue (index * 100 + value)
				done))
	in
	Array.iter (fun d -> ignore (Domain.join d)) domains;
	print_endline "[test] concurrent_enq_test: all producer domains joined";
	let seen = Hashtbl.create 128 in
	print_endline "[test] concurrent_enq_test: draining 100 values";
	for _ = 1 to 100 do
		match Flat_combining.Fc_queue.dequeue queue with
		| Some value -> Hashtbl.replace seen value true
		| None -> failwith "unexpected empty queue during drain"
	done;
	Printf.printf "[test] concurrent_enq_test: unique values observed=%d\n%!" (Hashtbl.length seen);
	if Hashtbl.length seen <> 100 then failwith "missing values in concurrent enqueue test"
	else print_endline "[test] concurrent_enq_test: passed"

let mixed_concurrent_test () =
	print_endline "[test] mixed_concurrent_test: start";
	let queue = Flat_combining.Fc_queue.create ~slots:8 () in
	print_endline "[test] mixed_concurrent_test: producer enqueues 1..100, consumer drains 100";
	let enqueuer =
		Domain.spawn (fun () ->
			for value = 1 to 100 do
				Flat_combining.Fc_queue.enqueue queue value
			done)
	in
	let dequeuer =
		Domain.spawn (fun () ->
			let rec consume count =
				if count = 100 then ()
				else
					match Flat_combining.Fc_queue.dequeue queue with
					| Some _ -> consume (count + 1)
					| None -> Domain.cpu_relax (); consume count
			in
			consume 0)
	in
	ignore (Domain.join enqueuer);
	print_endline "[test] mixed_concurrent_test: enqueuer joined";
	ignore (Domain.join dequeuer);
	print_endline "[test] mixed_concurrent_test: dequeuer joined";
	print_endline "[test] mixed_concurrent_test: passed"

let () =
	print_endline "[suite] manual tests: begin";
	sequential_test ();
	concurrent_enq_test ();
	mixed_concurrent_test ();
	print_endline "[suite] manual tests passed"

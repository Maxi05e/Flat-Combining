(** QCheck-Lin Linearizability Test for Flat-Combining Queue

    This test verifies that the flat-combining queue is linearizable
    under concurrent access. Linearizability is a strong consistency
    guarantee: all concurrent operations can be explained by some
    sequential ordering of those operations.

    == Design ==

    The flat-combining queue works by:
    1. Having each domain publish its operation to a slot
    2. One combiner serializes all operations by applying them to
       the sequential queue state
    3. The linearization point occurs when the combiner executes
       Q.apply, which atomically transitions the queue state

    We test two operations:
    - enqueue(x): Publishes x via atomic slot, combiner applies it
    - dequeue(): Returns Some x or None, atomically observed

    A small slot capacity (4) allows interesting interleavings while
    keeping the state space manageable for linearizability checking.

    == Expected Result ==

    This test should PASS. The atomic publication list and combiner
    election mechanism ensure that all operations can be linearized
    at the point where the combiner executes Q.apply on the shared
    queue state.
*)

open Lin

(** Linearizability test for flat-combining queue *)
module FC_QSig = struct
  type t = Flat_combining.Fc_queue.t

  let init () = Flat_combining.Fc_queue.create ~slots:4 ()

  let cleanup _ = ()

  let int_small = nat_small

  (** Wrap dequeue to return int: min_int for None (unambiguous sentinel),
      or the actual value for Some.
      Using min_int as sentinel avoids collision since nat_small generates 0-15 *)
  let dequeue_as_int q =
    match Flat_combining.Fc_queue.dequeue q with
    | Some x -> x
    | None -> min_int

  (** API specification for FC queue linearizability test.
      Both operations are non-blocking:
      - enqueue: always succeeds, returns unit
      - dequeue: returns min_int if empty, or the dequeued value
  *)
  let api =
    [
      val_ "enq" Flat_combining.Fc_queue.enqueue
        (t @-> int_small @-> returning unit);
      val_ "deq" dequeue_as_int (t @-> returning int_small);
    ]
end

module FC_Q_Domain = Lin_domain.Make (FC_QSig)

let () =
  QCheck_base_runner.run_tests_main
    [
      FC_Q_Domain.lin_test ~count:500
        ~name:"FC_queue linearizability (flat combining wrapper)";
    ]

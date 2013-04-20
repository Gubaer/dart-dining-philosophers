library dining_philosophers.dinner5;
/**
 * This is a solution for the dining philosopher problem based on
 * Dijkstras aproach.
 *
 * See *Resource hierarchy solution* in
 * http://en.wikipedia.org/wiki/Dining_philosophers_problem
 *
 * The solution consists of:
 *   * n actors for n dining philosophers
 *   * n actors for n forks
 *
 * Forks have a unique numeric id. They are partially orded
 * by this id.
 *
 * Philosophers are initialized with the send ports of their
 * left and right fork. Before they start dining, they receive
 * the ids of this forks. A philosopher always picks up the
 * fork with the lower id first. He releases forks in opposite
 * order.
 */

import "dart:isolate";
import "dart:math";
import "dart:async";

var _random = new Random();

/// completes after [delay] ms with value null
Future sleep(delay) => new Future.delayed(
    new Duration(milliseconds:delay), ()=>null);

/// completes after a random number of `ms` in the range
/// 0..[range] with value null
Future sleepRandom(range) => sleep(_random.nextInt(range));

/// initializes the table with the number of philosophers
class InitTable {
  /// the number of philosophers. n>=2 expected.
  final int n;
  InitTable(this.n) {
    assert(n >= 2);
  }
}

/// message to initialize a fork
class InitFork {
  final int id;
  InitFork(this.id);
}

class PickUp{}
class PutDown{}
class QueryId{}

/**
 * Represents a fork on the diner table.
 */
class Fork {

  bool inUse = false;
  int id;
  SendPort pending = null;

  Fork() {
    port.receive(handleInit);
  }

  /// handles messages when in state 'init'
  handleInit(message, replyTo) {
    assert(message is InitFork);
    this.id = message.id;
    port.receive(handleRequest);
    log("initialized");
  }

  /// handles messages after the initialization phase
  handleRequest(message, replyTo) {
    if (message is PickUp) {
      if (inUse) {
        log("pickup: already in use - remember request");
        pending = replyTo;
      } else {
        log("pickup: not in used yet - grant request");
        inUse = true;
        replyTo.send(true);
      }
    } else if (message is PutDown) {
      assert(inUse);
      if (pending != null) {
        log("putDown: grant to pending request");
        pending.send(true);
        pending = null;
      } else {
        log("putDown: free again");
        inUse = false;
      }
      replyTo.send(null);
    } else if (message is QueryId) {
      log("query id ...");
      replyTo.send(id);
    }
  }

  log(m) => print("fork $id: $m");
}

fork() => new Fork();

/// message sent to initialize a philosopher
class InitPhilosopher {
  final int id;
  final List<SendPort> forks;
  InitPhilosopher(this.id, this.forks);
}

/// message sent to start the dinner
class StartDinner{}


class Philosopher {
  int id;
  List forks;

  Philosopher() {
    port.receive(handleInit);
  }

  /// responds to messages when in 'init' state
  handleInit(message,replyTo) {
    if(message is InitPhilosopher) {
      id = message.id;
      forks = [];
      Future.forEach(message.forks, (f) =>
        f.call(new QueryId())
        .then((id) => forks.add({"id": id, "fork": f}))
      )
      .then((_) {
        forks.sort((a,b) => a["id"].compareTo(b["id"]));
        var fids = forks.map((f)=>f["id"]).join(",");
        log("init - forks: $fids");
      });
    } else if (message is StartDinner) {
      thinkAndEat();
    }
  }

  thinkAndEat() {
    think()
    .then((_) => pickUpForks())
    .then((_) => eat())
    .then((_) => putDownForks())
    .then((_) => thinkAndEat());
  }

  Future think() {
    log("thinking ...");
    return sleepRandom(2000);
  }

  Future eat() {
    log("eating ...");
    return sleepRandom(2000);
  }

  Future pickUpForks() {
    log("picking up forks ... START");
    return forks[0]["fork"].call(new PickUp())
    .then((_) {
      log("pick up: got fork ${forks[0]["id"]}");
      return forks[1]["fork"].call(new PickUp());
    }).then((_) {
      log("pick up: got fork ${forks[1]["id"]}");
      return new Future.value(null);
    });
  }

  Future putDownForks() {
    log("putting down forks ...");
    var msg = new PutDown();

    return forks[1]["fork"].call(msg)
    .then((_) => forks[0]["fork"].call(msg));
  }

  log(m) => print("philosopher $id: $m");
}

philosopher() => new Philosopher();


class Table {
  var philosophers = [];
  var forks = [];
  int n;

  Table(this.n) {
    initForks();
    initPhilosophers();
  }

  initForks() {
    for (int i=0; i<n; i++) {
      forks.add(spawnFunction(fork));
      forks[i].send(new InitFork(i));
    }
  }

  initPhilosophers() {
    for (int i=0; i<n; i++) {
      philosophers.add(spawnFunction(philosopher));
      var forks = [this.forks[i], this.forks[(i + n -1) % n]];
      philosophers[i].send(new InitPhilosopher(i, forks));
    }
  }

  dine() {
    var msg = new StartDinner();
    philosophers.forEach((p) => p.send(msg));
  }
}

dine(int n) {
  var table = new Table(n);
  table.dine();
}




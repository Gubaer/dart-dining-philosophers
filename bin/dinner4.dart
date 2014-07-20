import "package:args/args.dart";
import "dart:io";

import "package:dining_philosophers/dinner4.dart" as dinner4;

main(List<String> args) {
  var parser = new ArgParser();
  parser.addOption(
      "num-philosophers",
      abbr: "n",
      defaultsTo: "5",
      help: "the number of philosophers [n >= 2]");
  parser.addFlag("help", abbr: "h", negatable: false, help: "display help");
  var options = parser.parse(args);
  if (options["help"]) {
    print("usage: dart dinner4.dart [options]");
    print(parser.getUsage());
    exit(0);
  }

  var n = int.parse(options["num-philosophers"], onError: (source) {
    print("fatal: '$source' isn't a valid integer");
    exit(1);
  });
  if (n < 2) {
    print("fatal: $n is too small, >=2 required");
    exit(1);
  }
  print("starting a dinner with $n philosophers ...");
  dinner4.dine(n);
}

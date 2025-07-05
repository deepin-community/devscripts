#!/usr/bin/python3
import sys
from urllib.parse import quote


def main():
    required_args = {"TO", "SUBJECT", "BODY"}
    allowed_args = required_args | {"BCC", "CC"}

    if len(sys.argv) < 4:
        print("Usage: python3 -m devscripts.mailto KEY=<VALUE> ...")
        print("Required keys: " + ", ".join(sorted(required_args)))
        print("Supported keys: " + ", ".join(sorted(allowed_args)))
        print()
        print('The value can start with "@" to read the value from a file.')
        sys.exit(1)

    params = {}
    for arg in sys.argv[1:]:
        try:
            name, value = arg.split("=")
        except ValueError:
            error("All arguments must be K=V pairs")
        else:
            if name not in allowed_args:
                error(
                    "Unsupported key "
                    + name
                    + ": Must be one of: "
                    + str(sorted(allowed_args))
                )
            if value.startswith("@"):
                with open(value[1:], "rt", encoding="utf-8") as fd:
                    value = fd.read()
            params[name] = quote(value)

    if (params.keys() & required_args) < required_args:
        error("The following keys must be given: " + str(sorted(required_args)))

    to_part = params["TO"]
    del params["TO"]
    params_part = "&".join(k.lower() + "=" + v for k, v in params.items())
    url = "mailto:" + to_part + "?" + params_part
    print(url)
    sys.exit(0)


def error(msg):
    print("error: " + msg, file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
    main()

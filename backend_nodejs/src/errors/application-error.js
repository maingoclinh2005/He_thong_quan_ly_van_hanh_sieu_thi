// Domain failures carry a stable category; HTTP status mapping belongs to controllers.
class ApplicationError extends Error {
  constructor(kind, message) {
    super(message);
    this.name = "ApplicationError";
    this.kind = kind;
  }
}

module.exports = { ApplicationError };

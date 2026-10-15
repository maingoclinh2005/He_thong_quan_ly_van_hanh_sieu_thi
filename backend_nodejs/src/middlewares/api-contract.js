// Wire format is snake_case. Legacy domain objects are adapted only at HTTP boundaries.
const snake = (key) =>
  key
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .toLowerCase();
const camel = (key) =>
  key.replace(/_([a-z])/g, (_, letter) => letter.toUpperCase());
const forbidden = new Set(["__proto__", "constructor", "prototype"]);
const providerPath =
  /^\/(payments|webhook)\/(vnpay-return|vnpay-ipn|bank-webhook|sepay)\/?$/i;

function mapFields(
  value,
  { input = false, legacy = () => {} } = {},
  depth = 0,
) {
  if (depth > 64) throw new Error("Payload nesting exceeds API contract");
  if (Array.isArray(value))
    return value.map((item) => mapFields(item, { input, legacy }, depth + 1));
  if (!value || typeof value !== "object") return value;
  if (typeof value.toJSON === "function")
    return mapFields(value.toJSON(), { input, legacy }, depth + 1);
  const result = Object.create(null);
  // Explicit snake_case wins over an old duplicate response alias.
  const entries = Object.entries(value).sort(
    ([a], [b]) => Number(a === snake(a)) - Number(b === snake(b)),
  );
  for (const [key, item] of entries) {
    const normalized = snake(key);
    if (forbidden.has(key) || forbidden.has(normalized)) {
      if (input) throw new Error("Unsafe field");
      continue;
    }
    if (input && Object.hasOwn(result, normalized))
      throw new Error("Duplicate field aliases");
    if (input && key !== normalized) legacy();
    result[normalized] = mapFields(item, { input, legacy }, depth + 1);
  }
  if (input) {
    for (const key of Object.keys(result)) {
      const alias = camel(key);
      if (alias !== key && !forbidden.has(alias)) result[alias] = result[key];
    }
  }
  return result;
}

function apiContract(req, res, next) {
  // Never rename signed provider fields (vnp_*, RspCode, transferAmount, etc.).
  if (providerPath.test(req.path)) return next();
  const json = res.json.bind(res);
  res.json = (value) => json(mapFields(value));
  const legacy = () => res.setHeader("Deprecation", "@1792026000");
  try {
    if (
      req.body &&
      req.is(["application/json", "application/x-www-form-urlencoded"])
    ) {
      req.body = mapFields(req.body, { input: true, legacy });
    }
    // Express 5 exposes query as a getter; override only for this request.
    const query = mapFields({ ...req.query }, { input: true, legacy });
    Object.defineProperty(req, "query", { value: query, configurable: true });
  } catch {
    return res
      .status(400)
      .json({
        success: false,
        message: "Field API không hợp lệ hoặc trùng tên; hãy dùng snake_case.",
      });
  }
  next();
}

function retiredEndpoint(replacement) {
  return (req, res) =>
    res.status(410).json({
      success: false,
      message: "Endpoint cũ đã ngừng sử dụng. Hãy cập nhật ứng dụng.",
      replacement: replacement + req.url,
    });
}

module.exports = { apiContract, mapFields, retiredEndpoint };

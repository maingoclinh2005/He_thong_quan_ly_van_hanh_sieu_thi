const { ApplicationError } = require('../errors/application-error');
function quantity(value, { signed = false } = {}) {
  if (value == null || value === '' || typeof value === 'boolean')
    throw new ApplicationError('invalid', 'Thiếu số lượng hợp lệ');
  const number = Number(value);
  if (!Number.isSafeInteger(number) || (!signed && number < 0) || Math.abs(number) > 2147483647)
    throw new ApplicationError('invalid', 'Số lượng phải là số nguyên hợp lệ, không âm.');
  return number;
}
module.exports = { quantity };

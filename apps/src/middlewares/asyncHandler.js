// Express 4 tidak menangkap error dari fungsi async, jadi dibungkus di sini.
module.exports = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

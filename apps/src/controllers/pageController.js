// Controller hanya merender halaman.
// Semua fungsi JavaScript untuk tampilan ada di public/js (bukan di sini).
exports.home = (req, res) => res.render('index', { title: 'Task Board' });
exports.status = (req, res) => res.render('status', { title: 'Status Server' });

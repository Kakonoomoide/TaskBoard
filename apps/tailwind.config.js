/** @type {import('tailwindcss').Config} */
module.exports = {
  // Tailwind memindai file-file ini untuk mencari class yang dipakai.
  // public/js ikut dipindai karena ada class yang dipakai lewat JavaScript.
  content: ['./views/**/*.ejs', './public/js/**/*.js'],
  theme: { extend: {} },
  plugins: [],
};

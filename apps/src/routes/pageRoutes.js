const router = require('express').Router();
const pageController = require('../controllers/pageController');

router.get('/', pageController.home);
router.get('/status', pageController.status);

module.exports = router;

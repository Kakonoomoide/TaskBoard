const router = require('express').Router();
const taskController = require('../controllers/taskController');
const healthController = require('../controllers/healthController');

router.get('/health', healthController.check);

router.get('/tasks', taskController.list);
router.post('/tasks', taskController.create);
router.patch('/tasks/:id', taskController.updateStatus);
router.delete('/tasks/:id', taskController.remove);

module.exports = router;

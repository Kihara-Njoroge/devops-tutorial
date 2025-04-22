const express = require('express');
const mongoose = require('mongoose');
const cors = require('cors');
const winston = require('winston');
const promClient = require('prom-client');

// Set up Prometheus metrics collection
const collectDefaultMetrics = promClient.collectDefaultMetrics;
const Registry = promClient.Registry;
const register = new Registry();
collectDefaultMetrics({ register });

// Create custom metrics
const httpRequestDurationMicroseconds = new promClient.Histogram({
    name: 'http_request_duration_seconds',
    help: 'Duration of HTTP requests in seconds',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.1, 0.3, 0.5, 0.7, 1, 3, 5, 7, 10]
});
register.registerMetric(httpRequestDurationMicroseconds);

// Create a counter for application-specific metrics
const itemCounter = new promClient.Counter({
    name: 'items_created_total',
    help: 'Total number of items created'
});
register.registerMetric(itemCounter);

// Configure Winston logger
const logger = winston.createLogger({
    level: 'info',
    format: winston.format.combine(
        winston.format.timestamp(),
        winston.format.json()
    ),
    defaultMeta: { service: 'backend-service' },
    transports: [
        new winston.transports.Console(),
        new winston.transports.File({ filename: '/var/log/app/error.log', level: 'error' }),
        new winston.transports.File({ filename: '/var/log/app/combined.log' })
    ]
});

// If running in development mode, also log to the console with colorization
if (process.env.NODE_ENV !== 'production') {
    logger.add(new winston.transports.Console({
        format: winston.format.combine(
            winston.format.colorize(),
            winston.format.simple()
        )
    }));
}

const app = express();
const PORT = process.env.PORT || 3000;
const MONGO_URI = process.env.MONGO_URI || 'mongodb://database-service:27017/testapp';

// Middleware
app.use(cors());
app.use(express.json());

// Middleware to measure request duration
app.use((req, res, next) => {
    const start = Date.now();

    // Add a listener to track when the response is finished and record metrics
    res.on('finish', () => {
        const duration = Date.now() - start;
        httpRequestDurationMicroseconds
            .labels(req.method, req.path, res.statusCode)
            .observe(duration / 1000); // convert to seconds

        // Log request details
        logger.info({
            message: `HTTP ${req.method} ${req.path}`,
            method: req.method,
            path: req.path,
            statusCode: res.statusCode,
            duration: duration
        });
    });

    next();
});

// Connect to MongoDB
mongoose.connect(MONGO_URI, {
    useNewUrlParser: true,
    useUnifiedTopology: true
})
    .then(() => logger.info('Connected to MongoDB'))
    .catch(err => logger.error('MongoDB connection error:', err));

// Define Item schema
const ItemSchema = new mongoose.Schema({
    name: {
        type: String,
        required: true
    },
    createdAt: {
        type: Date,
        default: Date.now
    }
});

const Item = mongoose.model('Item', ItemSchema);

// Routes
app.get('/', (req, res) => {
    res.json({ message: 'Backend API is running' });
});

// Get all items
app.get('/items', async (req, res) => {
    try {
        const items = await Item.find().sort({ createdAt: -1 });
        res.json(items);
    } catch (err) {
        logger.error('Error fetching items:', err);
        res.status(500).json({ message: 'Server error' });
    }
});

// Create a new item
app.post('/items', async (req, res) => {
    try {
        const newItem = new Item({
            name: req.body.name
        });

        const savedItem = await newItem.save();

        // Increment the counter for created items
        itemCounter.inc();

        logger.info(`New item created: ${savedItem.name}`);
        res.status(201).json(savedItem);
    } catch (err) {
        logger.error('Error creating item:', err);
        res.status(400).json({ message: err.message });
    }
});

// Expose metrics endpoint for Prometheus scraping
app.get('/metrics', async (req, res) => {
    try {
        res.set('Content-Type', register.contentType);
        res.end(await register.metrics());
    } catch (err) {
        logger.error('Error generating metrics:', err);
        res.status(500).json({ message: 'Error generating metrics' });
    }
});

// Health check endpoint
app.get('/health', (req, res) => {
    res.status(200).json({ status: 'ok' });
});

// Start the server
app.listen(PORT, () => {
    logger.info(`Server running on port ${PORT}`);
});

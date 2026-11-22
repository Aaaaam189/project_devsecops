const amqp = require('amqplib');
let channel = null;

const buildRabbitMQUrl = () => {
  const host = process.env.RABBITMQ_HOST || 'rabbitmq';
  const port = process.env.RABBITMQ_PORT || '5672';
  const username = encodeURIComponent(process.env.RABBITMQ_USERNAME);
  const password = encodeURIComponent(process.env.RABBITMQ_PASSWORD);
  const virtualHost = encodeURIComponent(process.env.RABBITMQ_VIRTUAL_HOST || '/foundersync');

  return `amqp://${username}:${password}@${host}:${port}/${virtualHost}`;
};

const connectRabbitMQ = async () => {
  try {
    const connection = await amqp.connect(buildRabbitMQUrl());
    channel = await connection.createChannel();
    console.log('RabbitMQ Connected');
    // Reconnexion automatique si connexion perdue
    connection.on('close', () => {
      console.error('RabbitMQ déconnecté, reconnexion...');
      setTimeout(connectRabbitMQ, 5000);
    });

    return channel;
  } catch (error) {
    console.error('RabbitMQ Error:', error.message);
    setTimeout(connectRabbitMQ, 5000); // réessayer après 5s
  }
};
const getChannel = () => {
  if (!channel) throw new Error('RabbitMQ non connecté');
  return channel;
};

module.exports = { connectRabbitMQ, getChannel };
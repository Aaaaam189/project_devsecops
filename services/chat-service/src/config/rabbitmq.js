const fs = require('fs');
const amqp = require('amqplib');
let channel = null;

const buildRabbitMQUrl = () => {
  const host = process.env.RABBITMQ_HOST || 'rabbitmq';
  const port = process.env.RABBITMQ_PORT || '5672';
  const username = encodeURIComponent(process.env.RABBITMQ_USERNAME);
  const password = encodeURIComponent(process.env.RABBITMQ_PASSWORD);
  const virtualHost = encodeURIComponent(process.env.RABBITMQ_VIRTUAL_HOST || '/foundersync');

  const protocol = process.env.RABBITMQ_PROTOCOL || 'amqp';
  return `${protocol}://${username}:${password}@${host}:${port}/${virtualHost}`;
};

// TLS options for amqps. The broker's certificate is signed by a private CA
// (see k3d/scripts/create-rabbitmq-tls.sh), so Node needs that CA to verify
// it. Certificate and hostname checks stay ON (Node's default): passing
// `ca` replaces the built-in CA list, so only certificates signed by this CA
// are accepted. amqplib sets the TLS servername from the URL host.
//
// Fails closed: with amqps and no CA file this throws instead of falling
// back to an unverified connection.
const buildTlsOptions = () => {
  const protocol = process.env.RABBITMQ_PROTOCOL || 'amqp';
  if (protocol !== 'amqps') return undefined;

  const caFile = process.env.RABBITMQ_CA_FILE;
  if (!caFile) {
    throw new Error('RABBITMQ_CA_FILE must be set when RABBITMQ_PROTOCOL=amqps');
  }
  return { ca: [fs.readFileSync(caFile)] };
};

const connectRabbitMQ = async () => {
  try {
    const connection = await amqp.connect(buildRabbitMQUrl(), buildTlsOptions());
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
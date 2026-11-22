const mongoose = require("mongoose");
const connectDB = async () => {
  try {
    const mongoUri = process.env.MONGO_URI || [
      "mongodb://",
      `${encodeURIComponent(process.env.MONGO_USERNAME)}:${encodeURIComponent(process.env.MONGO_PASSWORD)}`,
      `@${process.env.MONGO_HOST || "mongodb"}:${process.env.MONGO_PORT || "27017"}/${process.env.MONGO_DATABASE || "chatdb"}`,
      "?authSource=admin",
    ].join("");

    await mongoose.connect(mongoUri);

    console.log("MongoDB Connected");
  } catch (error) {
    console.error("MongoDB Error:", error);

    process.exit(1);
  }
};
module.exports = connectDB;

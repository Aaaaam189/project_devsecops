const mongoose = require("mongoose");
const connectDB = async () => {
  try {
    const database = process.env.MONGO_DATABASE || "chatdb";
    const mongoUri = process.env.MONGO_URI || [
      "mongodb://",
      `${encodeURIComponent(process.env.MONGO_USERNAME)}:${encodeURIComponent(process.env.MONGO_PASSWORD)}`,
      `@${process.env.MONGO_HOST || "mongodb"}:${process.env.MONGO_PORT || "27017"}/${database}`,
      // A MongoDB user is looked up in the database it was created in. The chat
      // user is created in chatdb (k3d/charts/mongodb init script), so logging in
      // against "admin" fails with AuthenticationFailed (code 18).
      `?authSource=${process.env.MONGO_AUTH_SOURCE || database}`,
    ].join("");

    await mongoose.connect(mongoUri);

    console.log("MongoDB Connected");
  } catch (error) {
    console.error("MongoDB Error:", error);

    process.exit(1);
  }
};
module.exports = connectDB;

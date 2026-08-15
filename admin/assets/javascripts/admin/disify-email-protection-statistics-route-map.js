export default {
  resource: "admin.adminPlugins",
  path: "/plugins",
  map() {
    this.route("disifyEmailProtectionStatistics", {
      path: "/disify-email-protection-statistics",
    });
  },
};

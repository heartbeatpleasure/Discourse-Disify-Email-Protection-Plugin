export default {
  resource: "admin.adminPlugins",
  path: "/plugins",
  map() {
    this.route("disifyEmailProtectionHealth", {
      path: "/disify-email-protection-health",
    });
  },
};

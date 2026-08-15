export default {
  resource: "admin.adminPlugins",
  path: "/plugins",
  map() {
    this.route("disifyEmailProtectionTools", {
      path: "/disify-email-protection-tools",
    });
  },
};

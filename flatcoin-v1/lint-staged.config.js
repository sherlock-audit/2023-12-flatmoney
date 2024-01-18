module.exports = {
  "src/**/*.sol": ["prettier --write --plugin=prettier-plugin-solidity", "solhint --max-warnings 0"],
  "test/**/*.sol": "prettier --write --plugin=prettier-plugin-solidity",
  "{tasks,scripts}/**/*.{js,ts}": "prettier --write",
};

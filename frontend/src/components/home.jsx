import React from "react";
import { Link } from "react-router-dom";
import { FaUserShield, FaChartLine, FaRegClock } from "react-icons/fa";

const Home = () => {
  return (
    <div className="bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-600 min-h-screen text-white">
      {/* Navbar */}
      <nav className="flex justify-between items-center p-6">
        <div className="text-2xl font-bold text-white">VestaCoin</div>
        <ul className="flex space-x-8">
          <li><Link to="/" className="hover:text-gray-200">Home</Link></li>
          <li><Link to="/about" className="hover:text-gray-200">About</Link></li>
          <li><Link to="/contact" className="hover:text-gray-200">Contact</Link></li>
        </ul>
      </nav>

      {/* Hero Section */}
      <section className="h-screen flex flex-col justify-center items-center text-center space-y-6">
        <h1 className="text-5xl md:text-6xl font-extrabold animate__animated animate__fadeInUp">
          Unlock Your Future with Vesting Contracts
        </h1>
        <p className="text-lg md:text-xl font-medium animate__animated animate__fadeInUp animate__delay-1s">
          Empower employees and partners with secure, time-locked token distributions.
        </p>
        <div className="flex space-x-4 animate__animated animate__fadeInUp animate__delay-2s">
          <Link
            to="/get-started"
            className="px-6 py-3 bg-pink-500 hover:bg-pink-700 rounded-lg shadow-lg text-white font-semibold transition duration-300"
          >
            Get Started
          </Link>
          <Link
            to="/about"
            className="px-6 py-3 border-2 border-white hover:bg-white hover:text-pink-500 rounded-lg shadow-lg text-white font-semibold transition duration-300"
          >
            Learn More
          </Link>
        </div>
      </section>

      {/* About Us Section */}
      <section className="py-20 bg-gray-800">
        <div className="container mx-auto px-6 text-center">
          <h2 className="text-3xl font-bold text-white mb-8">What is VestaCoin?</h2>
          <p className="text-lg text-white mb-6">
            VestaCoin is a cutting-edge time-locked token vesting solution built on the Stacks blockchain. We ensure secure, transparent, and customizable token distribution for employees, partners, and investors. With features like cliff periods, revocable schedules, and penalties for early exits, we offer a reliable tool for long-term token management.
          </p>
        </div>
      </section>

      {/* Features Section with Cards */}
      <section className="py-20 bg-gray-900">
        <div className="container mx-auto px-6 text-center">
          <h2 className="text-3xl font-bold text-white mb-8">Key Features</h2>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-10">
            <div className="card bg-gray-800 p-6 rounded-lg shadow-lg text-white hover:scale-105 transition-all duration-300">
              <div className="flex justify-center mb-4">
                <FaUserShield className="text-4xl text-pink-500" />
              </div>
              <h3 className="text-xl font-semibold">Customizable Schedules</h3>
              <p>Set the vesting intervals that work for you – monthly, yearly, or customized.</p>
            </div>
            <div className="card bg-gray-800 p-6 rounded-lg shadow-lg text-white hover:scale-105 transition-all duration-300">
              <div className="flex justify-center mb-4">
                <FaChartLine className="text-4xl text-pink-500" />
              </div>
              <h3 className="text-xl font-semibold">Cliff Periods</h3>
              <p>Define cliff periods before tokens are released, ensuring a fair release schedule.</p>
            </div>
            <div className="card bg-gray-800 p-6 rounded-lg shadow-lg text-white hover:scale-105 transition-all duration-300">
              <div className="flex justify-center mb-4">
                <FaRegClock className="text-4xl text-pink-500" />
              </div>
              <h3 className="text-xl font-semibold">Revocable Schedules</h3>
              <p>Option to revoke schedules, with penalties for early exits.</p>
            </div>
          </div>
        </div>
      </section>

      {/* How It Works Section */}
      <section className="py-20 bg-gradient-to-r from-indigo-600 via-purple-600 to-pink-600">
        <div className="container mx-auto px-6 text-center text-white">
          <h2 className="text-3xl font-bold mb-8">How VestaCoin Works</h2>
          <p className="text-lg mb-8">
            VestaCoin is powered by a smart contract built on the Stacks blockchain, providing an immutable and transparent way to manage token vesting. Our platform enables businesses to set clear, enforceable vesting schedules that ensure fairness and security for all parties involved.
          </p>
          <div className="flex justify-center space-x-6">
            <div className="bg-white text-gray-800 p-6 rounded-lg shadow-xl w-60">
              <h4 className="font-semibold mb-3">Create Vesting Schedule</h4>
              <p>Setup schedules for token distribution with cliff periods and vesting intervals.</p>
            </div>
            <div className="bg-white text-gray-800 p-6 rounded-lg shadow-xl w-60">
              <h4 className="font-semibold mb-3">Claim Tokens</h4>
              <p>Beneficiaries can claim their tokens as they become vested according to the schedule.</p>
            </div>
            <div className="bg-white text-gray-800 p-6 rounded-lg shadow-xl w-60">
              <h4 className="font-semibold mb-3">Revocation</h4>
              <p>Schedules can be revoked with penalties for early exits, ensuring fairness.</p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer Section */}
      <footer className="bg-gray-900 py-6">
        <div className="text-center text-white">
          <p>© 2024 VestaCoin | All Rights Reserved</p>
        </div>
      </footer>
    </div>
  );
};

export default Home;

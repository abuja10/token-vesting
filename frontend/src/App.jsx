import { useState } from 'react';
import reactLogo from './assets/react.svg';
import './App.css';
import * as MicroStacks from '@micro-stacks/react';
import { WalletConnectButton } from './components/wallet-connect-button.jsx';
import { UserCard } from './components/user-card.jsx';
import { Logo } from './components/ustx-logo.jsx';
import { NetworkToggle } from './components/network-toggle.jsx';
import { BrowserRouter, Routes, Route } from "react-router-dom";
import React from "react";
import Home from './components/home.jsx';





export default function App () {
  return (
    <MicroStacks.ClientProvider
      appName={'React + micro-stacks'}
      appIconUrl={"reactLogo"}
    >
      {/* <Contents /> */}
      <BrowserRouter>
      <div className="bg-gray-100 min-h-screen">
        <Routes>
          <Route path="/" element={<Home/>} />
        </Routes>
      </div>
    </BrowserRouter>
    </MicroStacks.ClientProvider>

  );
};
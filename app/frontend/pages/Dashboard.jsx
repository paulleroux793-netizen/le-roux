import React from 'react'

export default function Dashboard() {
  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      <div className="max-w-7xl mx-auto px-4 py-12">
        <header className="mb-12">
          <h1 className="text-4xl font-bold text-gray-900 mb-2">
            Dr Chalita le Roux
          </h1>
          <p className="text-xl text-gray-600">AI Receptionist Dashboard</p>
        </header>

        <div className="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
          <div className="bg-white rounded-lg shadow-md p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-2">
              Today's Appointments
            </h2>
            <p className="text-3xl font-bold text-indigo-600">0</p>
            <p className="text-sm text-gray-500">Pending confirmations: 0</p>
          </div>

          <div className="bg-white rounded-lg shadow-md p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-2">
              WhatsApp Messages
            </h2>
            <p className="text-3xl font-bold text-green-600">0</p>
            <p className="text-sm text-gray-500">This week: 0</p>
          </div>

          <div className="bg-white rounded-lg shadow-md p-6">
            <h2 className="text-lg font-semibold text-gray-900 mb-2">
              Flagged Patients
            </h2>
            <p className="text-3xl font-bold text-amber-600">0</p>
            <p className="text-sm text-gray-500">Need follow-up: 0</p>
          </div>
        </div>

        <div className="bg-white rounded-lg shadow-md p-6">
          <h2 className="text-xl font-semibold text-gray-900 mb-4">
            System Status
          </h2>
          <div className="space-y-3">
            <div className="flex items-center justify-between">
              <span className="text-gray-700">Database</span>
              <span className="text-green-600 font-semibold">✓ Connected</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-gray-700">Google Calendar</span>
              <span className="text-gray-400 font-semibold">○ Pending</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-gray-700">Twilio WhatsApp</span>
              <span className="text-gray-400 font-semibold">○ Pending</span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-gray-700">Claude AI</span>
              <span className="text-gray-400 font-semibold">○ Pending</span>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

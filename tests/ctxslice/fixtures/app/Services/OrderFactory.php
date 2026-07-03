<?php

namespace App\Services;

use App\Models\Order;

class OrderFactory
{
    public function make(): Order
    {
        return new Order();
    }
}

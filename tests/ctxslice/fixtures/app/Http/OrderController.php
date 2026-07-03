<?php

namespace App\Http;

use App\Services\OrderService;

class OrderController
{
    public function show(OrderService $service, $order): int
    {
        return $service->total($order);
    }
}

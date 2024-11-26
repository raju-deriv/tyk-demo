import http from "k6/http";
import { check } from "k6";

const BASE_URL =
    "http://tyk-gateway.localhost:8080/api/v1";
// const BASE_URL =
//     "https://deriv-dev.outsystems.app/AdrienneTestAPIUnofficial/rest/benchmark";

const urls = ["/residence_list"];
// const urls = ["/residence_list", "/website_status", "/aggregated_calls"];

const params = {
    headers: {
        "X-Token": "a1-g2pf8z9co7OXcC74Xd0PQpFLDUsoA",
        "Cache-Control": "max-age=900",
    },
};

export const options = {
    scenarios: {
        fixed_requests: {
            executor: "shared-iterations",
            vus: 50,
            iterations: 1000,
            maxDuration: "30m",
        },
    },
};

export default function () {
    // Rotate through URLs sequentially
    const urlIndex = __ITER % urls.length;
    const url = `${BASE_URL}${urls[urlIndex]}`;

    // Send the request
    const response = http.get(url, {
        headers: {
            Accept: "application/json",
            // Add any other required headers
            "Cache-Control": "max-age=900",
        },
    });

    // Add checks to verify the response
    check(response, {
        "is status 200": (r) => r.status === 200,
    });
}